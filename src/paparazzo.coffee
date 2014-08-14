#
# Paparazzo.js: A MJPG proxy for the masses
#
#   paparazzo = new Paparazzo(options)
#
#   paparazzo.on "update", (image) => 
#     console.log "Downloaded #{image.length} bytes"
#
#   paparazzo.start()
#

http = require 'http'
EventEmitter = require('events').EventEmitter

class Paparazzo extends EventEmitter

  @image = ''

  constructor: (options) ->

    if not options.host?
      emitter.emit 'error',
        message: 'Host is not defined!'
    options.port or= 80
    options.path or= '/'
    options.headers or= {}
    @options = options
    @memory = options.memory or 8388608 # 8MB
    @data=''

  start: ->

    # To use EventEmitter in the callback, we must save our instance 'this'
    emitter = @

    request = http.get @options, (response) ->

      if response.statusCode != 200
        emitter.emit 'error',
          message: 'Server did not respond with HTTP 200 (OK).'
        return

      emitter.boundary = emitter.boundaryStringFromContentType response.headers['content-type']
      @data = ''

      response.setEncoding 'binary'
      response.on 'data', emitter.handleServerResponse
      response.on 'end', () ->
        emitter.emit 'error',
          message: "Server closed connection!"

    request.on 'error', (error) ->
      # Failed to connect
      emitter.emit 'error',
        message: error.message

  ###
  #
  # Find out the boundary string that delimits images.
  # If a boundary string is not found, it fallbacks to a default boundary.
  #
  ###
  boundaryStringFromContentType: (type) ->
    # M-JPEG content type looks like multipart/x-mixed-replace;boundary=<boundary-name>
    match = type.match(/multipart\/x-mixed-replace;\s*boundary=(.+)/)
    boundary = match[1] if match?.length > 1
    if not boundary?
      boundary = '--myboundary'
      @emit 'error',
        message: "Couldn't find a boundary string. Falling back to --myboundary."
    boundary

  ###
  #
  # Handles chunks of data sent by the server and restore images.
  #
  # A MJPG image boundary typically looks like this:
  # --myboundary
  # Content-Type: image/jpeg
  # Content-Length: 64199
  # \r\n
  #
  ###
  
  handleServerResponse: (chunk) =>
    @data += chunk
    first_boundary_index = @data.indexOf @boundary
    if first_boundary_index == -1 
      if @data.length >= @memory
        @data = ''
        @emit 'error',
          message: 'Data buffer just reached threshold, flushing memory'
      return 
    #process MJPEG boundary header
    typeMatches = @data.substr(first_boundary_index,100).match /Content-Type:\s+image\/jpeg\s+/
    lengthMatches = @data.substr(first_boundary_index,160).match /Content-Length:\s+(\d+)\s+/
    if lengthMatches? and lengthMatches.length > 1
      # Grab length of image
      imageBeginning = @data.indexOf(lengthMatches[0]) + lengthMatches[0].length
      imageExpectedLength = parseInt lengthMatches[1], 10
      if imageExpectedLength + imageBeginning <= @data.length
        #Now we got a new image
        @image = @data.substr imageBeginning, imageExpectedLength
        @emit 'update', @image
        @data = @data.substring imageBeginning+imageExpectedLength
        @handleServerResponse('') #re-curse just in case we got two JPEGs at a time
    else if typeMatches?
      # If Content-Length is not present, but Content-Type is
      imageBeginning = @data.indexOf(typeMatches[0]) + typeMatches[0].length
      #look for 2nd boundary
      second_boundary_index = @data.indexOf @boundary, imageBeginning
      if second_boundary_index == -1
        return # wait for next chunk
      @image = @data.substring imageBeginning, second_boundary_index
      @emit 'update', @image
      @data = @data.substring second_boundary_index
      @handleServerResponse('') #re-curse just in case we got two JPEGs at a time
    else #look for 2nd boundary
      second_boundary_index = @data.indexOf @boundary, first_boundary_index+@boundary.length
      if second_boundary_index == -1
        return # wait for next chunk
      @image = @data.substring first_boundary_index+@boundary.length, second_boundary_index
      @emit 'update', @image
      @data = @data.substring second_boundary_index
      chunk=''
      @handleServerResponse('') #re-curse just in case we got two JPEGs at a time
      @emit 'error',
        message: 'Could not find beginning of next image'

module.exports = Paparazzo
