Bacon = require 'baconjs'
carrier = require 'carrier'
hue = require 'node-hue-api'
net = require 'net'
winston = require 'winston'

winston.remove(winston.transports.Console)
winston.add(winston.transports.Console, { timestamp: ( -> new Date() ) })
console.log = winston.info

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
hueUsername = process.env.HOUMIO_PHILIPS_HUE_USERNAME || "developer"

exit = (msg) ->
  console.log msg
  process.exit 1

displayResult = (result) ->
  console.log JSON.stringify(result, null, 2)

displayError = (err) ->
  console.err err

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

isWriteMessage = (message) -> message.command is "write"

scaleByteToPercent = (oldValue) ->
  oldMin = 0
  oldMax = 255
  newMin = 0
  newMax = 100
  Math.floor (((oldValue - oldMin) * (newMax - newMin)) / (oldMax - oldMin)) + newMin

scaleByteTo359 = (oldValue) ->
  oldMin = 0
  oldMax = 255
  newMin = 0
  newMax = 359
  Math.floor (((oldValue - oldMin) * (newMax - newMin)) / (oldMax - oldMin)) + newMin

writeMessagesToHue = (api, bridgeSocket) ->
  toLines(bridgeSocket)
    .map JSON.parse
    .filter isWriteMessage
    .onValue (msg) ->
      state = hue.lightState.create()
      if msg.data.on then state.on() else state.off()
      if msg.data.on then state.brightness(scaleByteToPercent(msg.data.bri))
      if msg.data.hue and msg.data.saturation then state.hsl(scaleByteTo359(msg.data.hue), scaleByteToPercent(msg.data.saturation), scaleByteToPercent(msg.data.bri))
      api.setLightState(msg.data.protocolAddress, state)
        .then(displayResult)
        .fail(displayError)
        .done()

selectBridge = (bridges) ->
  if bridges.length == 0
    exit "No bridges found"
  else if bridges.length == 1
    connectHue bridges[0].ipaddress, hueUsername
  else
    exit "Multiple bridges found"

connectBridge = (api) -> () ->
  bridgeSocket = new net.Socket()
  bridgeSocket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    writeMessagesToHue api, bridgeSocket
    bridgeSocket.write (JSON.stringify { command: "driverReady", protocol: "philips-hue"}) + "\n"

connectHue = (hueIp, hueUsername) ->
  console.log "Using HOUMIO_BRIDGE=#{houmioBridge}"
  console.log "Using HOUMIO_PHILIPS_HUE_IP=#{hueIp}"
  console.log "Using HOUMIO_PHILIPS_HUE_USERNAME=#{hueUsername}"
  api = new hue.HueApi(hueIp, hueUsername)
  api.config().then(connectBridge(api)).done()

hue.nupnpSearch().then(selectBridge).done();
