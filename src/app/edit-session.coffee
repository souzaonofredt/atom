Point = require 'point'
Buffer = require 'buffer'
Renderer = require 'renderer'
Cursor = require 'cursor'
Selection = require 'selection'
EventEmitter = require 'event-emitter'
_ = require 'underscore'

module.exports =
class EditSession
  @idCounter: 1

  @deserialize: (state, editor, rootView) ->
    buffer = Buffer.deserialize(state.buffer, rootView.project)
    session = new EditSession(editor, buffer)
    session.setScrollTop(state.scrollTop)
    session.setScrollLeft(state.scrollLeft)
    session.setCursorScreenPosition(state.cursorScreenPosition)
    session

  scrollTop: 0
  scrollLeft: 0
  renderer: null
  cursors: null
  selections: null

  constructor: (@editor, @buffer) ->
    @id = @constructor.idCounter++
    @tabText = @editor.tabText
    @renderer = new Renderer(@buffer, { softWrapColumn: @editor.calcSoftWrapColumn(), tabText: @editor.tabText })
    @cursors = []
    @selections = []
    @addCursorAtScreenPosition([0, 0])

    @buffer.on "change.edit-session-#{@id}", (e) =>
      for selection in @getSelections()
        selection.handleBufferChange(e)

    @renderer.on "change.edit-session-#{@id}", (e) =>
      @trigger 'screen-lines-change', e
      @moveCursors (cursor) -> cursor.refreshScreenPosition() unless e.bufferChanged

  destroy: ->
    @buffer.off ".edit-session-#{@id}"
    @renderer.off ".edit-session-#{@id}"
    @renderer.destroy()

  serialize: ->
    buffer: @buffer.serialize()
    scrollTop: @getScrollTop()
    scrollLeft: @getScrollLeft()
    cursorScreenPosition: @getCursorScreenPosition().serialize()

  isEqual: (other) ->
    return false unless other instanceof EditSession
    @buffer == other.buffer and
      @scrollTop == other.getScrollTop() and
      @scrollLeft == other.getScrollLeft() and
      @getCursorScreenPosition().isEqual(other.getCursorScreenPosition())

  getRenderer: -> @renderer

  setScrollTop: (@scrollTop) ->
  getScrollTop: -> @scrollTop

  setScrollLeft: (@scrollLeft) ->
  getScrollLeft: -> @scrollLeft

  autoIndentEnabled: ->
    @editor.autoIndent

  screenPositionForBufferPosition: (bufferPosition, options) ->
    @renderer.screenPositionForBufferPosition(bufferPosition, options)

  bufferPositionForScreenPosition: (screenPosition, options) ->
    @renderer.bufferPositionForScreenPosition(screenPosition, options)

  clipScreenPosition: (screenPosition, options) ->
    @renderer.clipScreenPosition(screenPosition, options)

  clipBufferPosition: (bufferPosition, options) ->
    @renderer.clipBufferPosition(bufferPosition, options)

  getEofBufferPosition: ->
    @buffer.getEofPosition()

  bufferRangeForBufferRow: (row) ->
    @buffer.rangeForRow(row)

  lineForBufferRow: (row) ->
    @buffer.lineForRow(row)

  scanInRange: (args...) ->
    @buffer.scanInRange(args...)

  backwardsScanInRange: (args...) ->
    @buffer.backwardsScanInRange(args...)

  getCurrentMode: ->
    @buffer.getMode()

  insertText: (text) ->
    @mutateSelectedText (selection) -> selection.insertText(text)

  destroyFoldsContainingBufferRow: (bufferRow) ->
    @renderer.destroyFoldsContainingBufferRow(bufferRow)

  mutateSelectedText: (fn) ->
    selections = @getSelections()
    @buffer.startUndoBatch(@getSelectedBufferRanges())
    fn(selection) for selection in selections
    @buffer.endUndoBatch(@getSelectedBufferRanges())

  stateForScreenRow: (screenRow) ->
    @renderer.stateForScreenRow(screenRow)

  getCursors: -> new Array(@cursors...)
  getSelections: -> new Array(@selections...)

  addCursorAtScreenPosition: (screenPosition) ->
    @addCursor(new Cursor(editSession: this, screenPosition: screenPosition))

  addCursorAtBufferPosition: (bufferPosition) ->
    @addCursor(new Cursor(editSession: this, bufferPosition: bufferPosition))

  addCursor: (cursor=new Cursor(editSession: this, screenPosition: [0,0])) ->
    @cursors.push(cursor)
    @trigger 'add-cursor', cursor
    @addSelectionForCursor(cursor)
    cursor

  removeCursor: (cursor) ->
    _.remove(@cursors, cursor)

  addSelectionForCursor: (cursor) ->
    selection = new Selection(editSession: this, cursor: cursor)
    @selections.push(selection)
    @trigger 'add-selection', selection
    selection

  removeSelection: (selection) ->
    _.remove(@selections, selection)

  getLastCursor: ->
    _.last(@cursors)

  setCursorScreenPosition: (position) ->
    @moveCursors (cursor) -> cursor.setScreenPosition(position)

  getCursorScreenPosition: ->
    @getLastCursor().getScreenPosition()

  setCursorBufferPosition: (position) ->
    @moveCursors (cursor) -> cursor.setBufferPosition(position)

  getCursorBufferPosition: ->
    @getLastCursor().getBufferPosition()

  getSelectedBufferRanges: ->
    selection.getBufferRange() for selection in @selections

  moveCursorUp: ->
    @moveCursors (cursor) -> cursor.moveUp()

  moveCursorDown: ->
    @moveCursors (cursor) -> cursor.moveDown()

  moveCursorLeft: ->
    @moveCursors (cursor) -> cursor.moveLeft()

  moveCursorRight: ->
    @moveCursors (cursor) -> cursor.moveRight()

  moveCursorToTop: ->
    @moveCursors (cursor) -> cursor.moveToTop()

  moveCursorToBottom: ->
    @moveCursors (cursor) -> cursor.moveToBottom()

  moveCursorToBeginningOfLine: ->
    @moveCursors (cursor) -> cursor.moveToBeginningOfLine()

  moveCursorToFirstCharacterOfLine: ->
    @moveCursors (cursor) -> cursor.moveToFirstCharacterOfLine()

  moveCursorToEndOfLine: ->
    @moveCursors (cursor) -> cursor.moveToEndOfLine()

  moveCursorToNextWord: ->
    @moveCursors (cursor) -> cursor.moveToNextWord()

  moveCursorToBeginningOfWord: ->
    @moveCursors (cursor) -> cursor.moveToBeginningOfWord()

  moveCursorToEndOfWord: ->
    @moveCursors (cursor) -> cursor.moveToEndOfWord()

  moveCursors: (fn) ->
    fn(cursor) for cursor in @getCursors()
    @mergeCursors()

  mergeCursors: ->
    positions = []
    for cursor in new Array(@getCursors()...)
      position = cursor.getBufferPosition().toString()
      if position in positions
        cursor.destroy()
      else
        positions.push(position)

_.extend(EditSession.prototype, EventEmitter)
