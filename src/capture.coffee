# Description:
#   Record video
#
# Commands:
#   [good|bad|park]: <comment> - store a comment
#   hubot record - show all comments in the last 2 weeks
#   hubot record <month>/<day>[/<year>] - show all comments since <month>/<day>[/<year>]
#   hubot record <month>/<day>[/<year>] <month>/<day>[/<year>] - show all comments between the given dates

cronJob = require('cron').CronJob
chrono = require 'chrono-node'
# require 'moment-duration-format'
moment = require 'moment'
_ = require 'underscore'

module.exports = (robot) ->
  # Compares current time to the time of the scheduled recording
  # to see if it should be fired.

  recordingShouldFire = (recording) ->
    recordingTime = recording.time
    utc = recording.utc
    now = new Date
    currentHours = undefined
    currentMinutes = undefined
    if utc
      currentHours = now.getUTCHours() + parseInt(utc, 10)
      currentMinutes = now.getUTCMinutes()
      if currentHours > 23
        currentHours -= 23
    else
      currentHours = now.getHours()
      currentMinutes = now.getMinutes()
    recordingHours = recordingTime.split(':')[0]
    recordingMinutes = recordingTime.split(':')[1]
    try
      recordingHours = parseInt(recordingHours, 10)
      recordingMinutes = parseInt(recordingMinutes, 10)
    catch _error
      return false
    if recordingHours == currentHours and recordingMinutes == currentMinutes
      return true
    false

  # Returns all scheduled recordings.

  getRecordings = ->
    robot.brain.get('recordings') or []

  # Returns just recordings for a given room.

  getRecordingsForRoom = (room) ->
    _.where getRecordings(), room: room

  # Gets all recordings and fire scheduled recordings.

  checkRecordings = ->
    recordings = getRecordings()
    _.chain(recordings).filter(recordingShouldFire).pluck('room').each doRecording

  # Fires the recording message.

  doRecording = (room) ->
    # TODO: change to initiate video recording and REMOVE SCHEDULER FROM BRAIN
    message = '🎥 Setting up my camera gear...\n🎬 Rolling...'
    robot.messageRoom room, message

  # Finds the room for most adaptors

  findRoom = (msg) ->
    room = msg.envelope.room
    if _.isUndefined(room)
      room = msg.envelope.user.reply_to
    room

  # Stores a recording in the brain.

  saveRecording = (room, time, utc) ->
    recordings = getRecordings()
    newRecording =
      time: time
      room: room
      utc: utc
    recordings.push newRecording
    updateBrain recordings

  # Updates the brain's recording knowledge.

  updateBrain = (recordings) ->
    robot.brain.set 'recordings', recordings

  clearScheduledRecordingsFromRoom = (room) ->
    recordings = getRecordings()
    recordingsToKeep = _.reject(recordings, room: room)
    updateBrain recordingsToKeep
    recordings.length - (recordingsToKeep.length)

  # Check for recordings that need to be fired, once a minute
  # Monday to Sunday.
  new cronJob('1 * * * * 0-6', checkRecordings, null, true)

  robot.respond /(record)\s*(now|start)?\s?([^.]+)?$/i, (msg) ->
    doRecording(findRoom(msg))
    # clearScheduledRecordingsFromRoom(findRoom(msg))
  robot.respond /(record)\s*(stop)?\s?([^.]+)?$/i, (msg) ->
    # TODO: make a stop function
  robot.respond /(record)\s*(status|st)?\s?([^.]+)?$/i, (msg) ->
    msg.send 'Your current status is...'
  robot.respond /(record)\s*(bookmark)?\s?([^.]+)?$/i, (msg) ->
    msg.send 'Bookmark added.'
  robot.respond /(record)\s*(remove)?\s?([^.]+)?$/i, (msg) ->
    msg.send 'Deleted previous bookmark'
  robot.respond /(record)\s*(delete)?\s?([^.]+)?$/i, (msg) ->
    # TODO: If currently recording, send delete. If scheduled recording, delete schedule.
    recordingsCleared = clearScheduledRecordingsFromRoom(findRoom(msg))
    msg.send 'Deleted ' + recordingsCleared + ' recording' + (if recordingsCleared == 1 then '' else 's') + '. No more recordings for you.'
  robot.respond /(record)\s*(at|in)?\s?([^.]+)?$/i, (msg) ->
    naturalTime = msg.match[2]
    timeStamp = chrono.parseDate(naturalTime)
    momentTime = moment(timeStamp)
    minutes = ''
    if timeStamp.getMinutes() < 10
      minutes = '0' + timeStamp.getMinutes().toString()
    else
      minutes = timeStamp.getMinutes().toString()
    time = timeStamp.getHours().toString() + ':' + minutes
    console.log '######################################'
    console.log 'NATURAL TIME:', naturalTime
    console.log 'TIME STAMP:', timeStamp
    console.log '######################################'
    room = findRoom(msg)
    saveRecording room, time
    msg.send 'Okay, I will start recording at ' + momentTime.format('h:mm A') + ' Eastern Time.'
  robot.respond /(record)\s*(list)?\s?([^.]+)?$/i, recList ->
    recordings = getRecordingsForRoom(findRoom(msg))
    if recordings.length == 0
      msg.send 'You don\'t have any recordings scheduled.'
    else
      recordingsText = [ 'Here are your scheduled recordings:' ].concat(_.map(recordings, (recording) ->
        if recording.utc
          recording.time + ' UTC' + recording.utc
        else
          recording.time + ' ET'
      ))
      msg.send recordingsText.join('\n')
  robot.respond /list recordings in every room/i, (msg) ->
    recordings = getRecordings()
    if recordings.length == 0
      msg.send 'No rooms currently recording.'
    else
      recordingsText = [ 'Here are all of the active recordings:' ].concat(_.map(recordings, (recording) ->
        'Room: ' + recording.room + ', Time: ' + recording.time
      ))
      msg.send recordingsText.join('\n')
  robot.respond /record help/i, (msg) ->
    message = []
    message.push 'I can remind you to do your daily recording!'
    message.push 'Use me to create a recording, and then I\'ll post in this room every weekday at the time you specify. Here\'s how:'
    message.push ''
    message.push robot.name + ' create recording hh:mm - I\'ll remind you to recording in this room at hh:mm every weekday.'
    message.push robot.name + ' create recording hh:mm UTC+2 - I\'ll remind you to recording in this room at hh:mm every weekday.'
    message.push robot.name + ' list recordings - See all recordings for this room.'
    message.push robot.name + ' list recordings in every room - Be nosey and see when other rooms have their recording.'
    message.push robot.name + ' delete hh:mm recording - If you have a recording at hh:mm, I\'ll delete it.'
    message.push robot.name + ' delete all recordings - Deletes all recordings for this room.'
    msg.send message.join('\n')
