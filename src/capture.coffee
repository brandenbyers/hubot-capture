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
    saveRecording room
    message = '🎥 Setting up my camera gear...\n🎬 Rolling...'
    robot.messageRoom room, message

  # Add a bookmark to active recording

  addBookmark = (room, activeRecording, bookmarkTitle) ->
    bookmark = {
      milliseconds: Date.now()
      bookmarkTitle: bookmarkTitle
    }
    active = activeRecording[0]
    active.book.push bookmark
    allBookmarks = active.book
    console.log '### allBookmarks', allBookmarks
    message = "🔖 #{bookmarkTitle} bookmark added (total bookmarks: #{allBookmarks.length})"
    robot.messageRoom room, message

  # Finds the room for most adaptors

  findRoom = (msg) ->
    room = msg.envelope.room
    if _.isUndefined(room)
      room = msg.envelope.user.reply_to
    room

  # Stores active recording to the brain

  saveRecording = (room, bookmarks = []) ->
    recordings = getRecordings()
    newRecording =
      time: '00:00'
      room: room
      start: Date.now()
      book: bookmarks
      active: true
    recordings.push newRecording
    updateBrain recordings

  # Stores a scheduled recording in the brain.

  saveFutureRecording = (room, time, utc) ->
    recordings = getRecordings()
    newRecording =
      time: time
      room: room
      utc: utc
    recordings.push newRecording
    updateBrain recordings

  stopRecording = (room, activeRecording) ->


  # Updates the brain's recording knowledge.

  updateBrain = (recordings) ->
    console.log recordings
    console.log robot.brain.get('recordings') or []
    robot.brain.set 'recordings', recordings

  clearScheduledRecordingsFromRoom = (room) ->
    recordings = getRecordings()
    recordingsToKeep = _.reject(recordings, room: room)
    updateBrain recordingsToKeep
    recordings.length - (recordingsToKeep.length)

  # Check for recordings that need to be fired, once a minute
  # Monday to Sunday.
  new cronJob('1 * * * * 0-6', checkRecordings, null, true)

  robot.respond /record now/i, (msg) ->
    room = findRoom msg
    clearScheduledRecordingsFromRoom room
    doRecording room
  robot.respond /record stop/i, (msg) ->
    room = findRoom msg
    recordings = getRecordings()
    recordingsCount = _.filter(recordings, room: room)
    activeRecording = _.filter(recordingsCount, active: true)
    if activeRecording.length < 1
      return msg.send 'Stop what? There is no active recording.'
    stopRecording room, activeRecording
  robot.respond /record status/i, (msg) ->
    msg.send 'Your current status is...'
  robot.respond /((record\s*)?(book)?mark)\s*(.{3,})*$/i, (msg) ->
    room = findRoom msg
    bookmarkTitle = msg.match[4]
    recordings = getRecordings()
    recordingsCount = _.filter(recordings, room: room)
    activeRecording = _.filter(recordingsCount, active: true)
    if activeRecording.length < 1
      return msg.send 'We aren\'t recording right now. What would you like me to bookmark? How about I bookmark your face with my robotic fist?'
    addBookmark room, activeRecording, bookmarkTitle
  robot.respond /record delete/i, (msg) ->
    recordingsCleared = clearScheduledRecordingsFromRoom(findRoom(msg))
    msg.send 'Deleted ' + recordingsCleared + ' recording' + (if recordingsCleared == 1 then '' else 's') + '. No more recordings for you.'
  robot.respond /record the future (.{3,})$/i, (msg) ->
    recordings = getRecordings()
    recordingsCount = _.filter(recordings, room: findRoom(msg))
    activeRecording = _.filter(recordingsCount, active: true)
    if activeRecording.length is 1
      return msg.send 'Recording in progress. To set a future recording time please stop the active recording first.'
    if recordingsCount.length > 0
      return msg.send 'You can only schedule one future recording per room.\n\nIf you would like to change your recording time, please delete the previous one first by typing `. record delete`.'
    naturalTime = msg.match[1]
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
    saveFutureRecording room, time
    msg.send 'Okay, I will start recording at ' + momentTime.format('h:mm A') + ' Eastern Time.'
  robot.respond /record list/i, (msg) ->
    recordings = getRecordingsForRoom(findRoom(msg))
    recordingsCount = _.filter(recordings, active: true)
    if recordingsCount.length is 1
      return msg.send 'There is no list. I\'m recording you right now.'
    if recordings.length == 0
      msg.send 'You have not scheduled a recording yet.'
    else
      recordingsText = [ 'I am scheduled to record at:' ].concat(_.map(recordings, (recording) ->
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
      recordingsText = [ 'Here are all of the active/scheduled recordings:' ].concat(_.map(recordings, (recording) ->
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
