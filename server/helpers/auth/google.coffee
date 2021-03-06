'use strict'

exports = module.exports = (User, googleapis, config, logger, moment) ->
  oauth2 = googleapis.oauth2('v2')
  calendar = googleapis.calendar('v3')

  class GoogleAuth

    authenticate: (authCode, clientId, redirect_uri, callback) ->
      oauth2Client = buildAuthClient clientId, redirect_uri
      getAuthToken authCode, oauth2Client, (err, tokens) ->
        oauth2Client.setCredentials(tokens)
        callback err, oauth2Client, tokens

    getUserInfo: (oauth2Client, callback) ->
      oauth2.userinfo.get {
        auth: oauth2Client
      }, (err, googleUser) ->
#        if not googleUser.auth
#          err = new Error("Googleapis returned user with no auth")
        if err
          logger.error "Googleapis User Info Error:", err
        callback err, googleUser

    getCalendarEventsList: (oauth2Client, callback) ->
      calendar.events.list {
        calendarId: 'primary'
        auth: oauth2Client
      }, (err, events)->
        if err
          logger.error "Googleapis Calendar Events Error:", err
        callback err, events

    getCalendarFreeBusy: (oauth2Client, startTime, callback) ->
      getCalendarFreeBusy(oauth2Client, startTime)
      .then (cals) ->
        callback null, cals
      .catch (err) ->
        callback err

    getCalendarsFromUsers: (userList ,startTime, callback) ->
      busyFreePromiseList = []
      for user in userList
        getStoredAuthClient user, (err, oauth2Client) ->
          if oauth2Client
            busyFreePromise = getCalendarFreeBusy(oauth2Client, startTime)
            busyFreePromiseList.push busyFreePromise
          else
            busyFreePromiseList.push Promise.reject(err)

      Promise.all(busyFreePromiseList).then (eventsList) ->
        callback(null, eventsList)
      .catch (errors) ->
        callback(errors)

    getAuthClient: (user, callback) ->
      return getStoredAuthClient user, (err, oauth2Client) ->
        callback err, oauth2Client

    sendCalendarInvite: (oauth2Client, meetingInfo, callback) ->
      event =
        summary: meetingInfo.meetingSummary,
        location: meetingInfo.meetingLocation,
        start:
          dateTime: meetingInfo.timeSlot.start
        end:
          dateTime: meetingInfo.timeSlot.end
        attendees: meetingInfo.meetingAttendees
        description: description

      calendar.events.insert {
        auth: oauth2Client
        calendarId: 'primary'
        resource: event
        sendNotifications: true
      }, (err, event) ->
        if err
          logger.error 'There was an error contacting the Calendar service: ', err
        else
          logger.info 'Event created: ' + event.htmlLink
        callback(err, event)

    getUserTimezone: (oauth2Client, callback) ->
      calendar.settings.get {
        auth: oauth2Client
        setting: "timezone"
      }, (err, settings) ->
        if err
          logger.error "GoogleApis settings error:", err
        callback err, settings

  # Private Methods
  getStoredAuthClient = (user, callback) ->
    clientId = config.googleAuthConfig.clientId
    redirectUri = config.googleAuthConfig.redirectUri
    oauth2Client = buildAuthClient clientId, redirectUri

    if !user.auth
      errorMessage = "Googleapis Auth token not stored for:" + user.email
      logger.error errorMessage
      return callback(new Error(errorMessage))
    oauth2Client.setCredentials user.auth

    # Need to refresh access token
    expiry_date = moment(parseInt(user.auth.expiry_date))
    if expiry_date.unix() < moment().unix()
      logger.info("Refreshing Access Token")
      tokenPromise = refreshAccessToken(oauth2Client)
      tokenPromise
      .then (tokens)->
        User.methods.updateAuth user.id, tokens, () ->
        oauth2Client.setCredentials tokens
        callback(null, oauth2Client)
      .catch (err) ->
        callback(err)
    else
      callback(null, oauth2Client)

  getAuthToken = (authCode, oauth2Client, callback)->
    oauth2Client.getToken authCode, (err, tokens)->
      if err
        logger.error "Googleapis Token Error:", err
      return callback err, tokens

  refreshAccessToken = (oauth2Client) ->
    tokensPromise = new Promise (resolve, reject) ->
      oauth2Client.refreshAccessToken (err, tokens)->
        if err
          logger.error "Refresh Access Token Error:", err
          reject(err)
        else
          resolve(tokens)
    return tokensPromise

  buildAuthClient = (clientId, redirectUri)->
    secret = config.googleAuthConfig.clientSecret
    OAuth2 = googleapis.auth.OAuth2
    oauth2Client = new OAuth2 clientId, secret, redirectUri
    return oauth2Client

  getCalendarIds = (oauth2Client, callback) ->
    calendar.calendarList.list {
      auth: oauth2Client
      minAccessRole: 'owner'
    }, (err, calendarIds) ->
      if err
        logger.error "Get Calendar Ids Error:", err
      callback(err, calendarIds)

  getCalendarFreeBusy = (oauth2Client, startTime) ->
    start = if startTime then moment(startTime) else moment()
    weekFromStart = moment(start).add(1, 'weeks')
    return new Promise (resolve, reject) ->
      getCalendarIds oauth2Client, (err, calendarList) ->
        if err
          reject err
        calendarIds = ({id: cal.id} for cal in calendarList.items)
        calendar.freebusy.query {
          resource:
            timeMin: start.toISOString()
            timeMax: weekFromStart.toISOString()
            items: calendarIds
          auth: oauth2Client
        }, (err, busyFree)->
          if err
            logger.error "Googleapis Calendar Events Error:", err
            reject err
          else
            resolve busyFree

  return new GoogleAuth()

description = "<div class=\"container\" style=\"width: 320px; margin-top: 40px; padding: 10px 10px; background-color: #d9d9d9; border-radius: 6px; text-align: center;\">\n<h4 style=\"margin-bottom: 0;\">This meeting was scheduled with</h4>\n<h2 style=\"margin-top: 0; margin-bottom: 30px;\">Tandem Scheduler</h2>\n<p style=\"text-align: center;\">Do you want to schedule meetings in <strong>less than 30</strong> seconds?<br/><br/>\n    <a href=\"https://betandem.com\" target=\"_blank\">Learn More</a> | <a href=\"https://beta.betandem.com\" target=\"_blank\">Try out our beta!</a>\n</p>\n<h6 style=\"margin-top:10px; text-align:center;\">Have feedback to make Tandem better? &nbsp;<a href=\"mailto:tandemscheduler@gmail.com?subject=Tandem Scheduler Feedback\">Send us a messsage</a></h6>\n</div>\n"



exports['@require'] = ['models/user', 'googleapis', 'config', 'logger', 'moment']