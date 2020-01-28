# Example key mapping (@keyMapping):
#   i:
#     command: "enterInsertMode", ... # This is a registryEntry object (as too are the other commands).
#   g:
#     g:
#       command: "scrollToTop", ...
#     t:
#       command: "nextTab", ...
#
# This key-mapping structure is generated by Commands.generateKeyStateMapping() and may be arbitrarily deep.
# Observe that @keyMapping["g"] is itself also a valid key mapping.  At any point, the key state (@keyState)
# consists of a (non-empty) list of such mappings.

class KeyHandlerMode extends Mode
  setKeyMapping: (@keyMapping) -> @reset()
  setPassKeys: (@passKeys) -> @reset()
  # Only for tests.
  setCommandHandler: (@commandHandler) ->

  # Reset the key state, optionally retaining the count provided.
  reset: (@countPrefix = 0) ->
    @keyState = [@keyMapping]

  constructor: (options) ->
    @commandHandler = options.commandHandler ? (->)
    @setKeyMapping options.keyMapping ? {}

    super extend options,
      keydown: @onKeydown.bind this

    if options.exitOnEscape
      # If we're part way through a command's key sequence, then a first Escape should reset the key state,
      # and only a second Escape should actually exit this mode.
      @push
        _name: "key-handler-escape-listener"
        keydown: (event) =>
          if KeyboardUtils.isEscape(event) and not @isInResetState()
            @reset()
            @suppressEvent
          else
            @continueBubbling

  onKeydown: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    isEscape = KeyboardUtils.isEscape event
    if isEscape and (@countPrefix != 0 or @keyState.length != 1)
      DomUtils.consumeKeyup event, => @reset()
    # If the help dialog loses the focus, then Escape should hide it; see point 2 in #2045.
    else if isEscape and HelpDialog?.isShowing()
      HelpDialog.toggle()
      @suppressEvent
    else if isEscape
      @continueBubbling
    else if @isMappedKey keyChar
      @handleKeyChar keyChar
      @suppressEvent
    else if @isCountKey keyChar
      digit = parseInt keyChar
      @reset if @keyState.length == 1 then @countPrefix * 10 + digit else digit
      @suppressEvent
    else
      @reset() if keyChar
      @continueBubbling

  # This tests whether there is a mapping of keyChar in the current key state (and accounts for pass keys).
  isMappedKey: (keyChar) ->
    (mapping for mapping in @keyState when keyChar of mapping)[0]? and not @isPassKey keyChar

  # This tests whether keyChar is a digit (and accounts for pass keys).
  isCountKey: (keyChar) ->
    keyChar and (if 0 < @countPrefix then '0' else '1') <= keyChar <= '9' and not @isPassKey keyChar

  # Keystrokes are *never* considered pass keys if the user has begun entering a command.  So, for example, if
  # 't' is a passKey, then the "t"-s of 'gt' and '99t' are neverthless handled as regular keys.
  isPassKey: (keyChar) ->
    # Find all *continuation* mappings for keyChar in the current key state (i.e. not the full key mapping).
    mappings = (mapping for mapping in @keyState when keyChar of mapping and mapping != @keyMapping)
    # If there are no continuation mappings, and there's no count prefix, and keyChar is a pass key, then
    # it's a pass key.
    mappings.length == 0 and @countPrefix == 0 and keyChar in (@passKeys ? "")

  isInResetState: ->
    @countPrefix == 0 and @keyState.length == 1

  handleKeyChar: (keyChar) ->
    bgLog "handle key #{keyChar} (#{@name})"
    # A count prefix applies only so long a keyChar is mapped in @keyState[0]; e.g. 7gj should be 1j.
    @countPrefix = 0 unless keyChar of @keyState[0]
    # Advance the key state.  The new key state is the current mappings of keyChar, plus @keyMapping.
    @keyState = [(mapping[keyChar] for mapping in @keyState when keyChar of mapping)..., @keyMapping]
    if @keyState[0].command?
      command = @keyState[0]
      count = if 0 < @countPrefix then @countPrefix else 1
      bgLog "  invoke #{command.command} count=#{count} "
      @reset()
      @commandHandler {command, count}
      @exit() if @options.count? and --@options.count <= 0
    @suppressEvent

root = exports ? (window.root ?= {})
root.KeyHandlerMode = KeyHandlerMode
extend window, root unless exports?
