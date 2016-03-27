Meeting = require "../models/meeting"
User = require "../models/user"
googleAuth = require "../helpers/auth/google"
CalendarParser = require "../helpers/calendar_parser"

meetingController =

  addEmail: (req, res) ->
    meeting_id = req.body.meeting_id
    email = req.body.email

    cursor = Meeting.methods.findById(meeting_id)
    cursor.on 'data', (doc) ->

      # Update the email list && save to meeting
      initiator = doc.meeting_initiator
      emails = doc.emails
      timezone = doc.timezone
      lenInMin = doc.length_in_min
      if emails
        if !inEmailList(email, emails)
          emails.push email
      else
        emails = [email]

      Meeting.methods.update(meeting_id, {emails: emails})

      # Append meeting initiator to schedule
      if !inEmailList initiator, emails
        emails.push initiator

      # Build out calendar data
      UsersFromEmails emails, (err, users) ->
        googleAuth.getCalendarsFromUsers users, (cals) ->
          calendarParser = new CalendarParser(timezone, lenInMin)
          availability = calendarParser.buildMeetingCalendar(cals)
          response = {}
          response.tandem_users = ({name: user.name, email: user.email} for user in users)
          response.schedule = availability
          res.status(200).send response

  removeEmail: (req, res) ->
    response = {}
    meeting_id = req.query.meeting_id
    email = req.query.email
    cursor = Meeting.methods.findById(meeting_id)
    cursor.on 'data', (doc) ->
      initiator = doc.meeting_initiator
      emails = doc.emails
      timezone = doc.timezone
      lenInMin = doc.length_in_min
      if emails
        if inEmailList(email, emails)
          index = emails.indexOf email
          emails.splice(index, 1)

      Meeting.methods.update(meeting_id, {emails: emails})

      # Append meeting initiator to schedule
      if !inEmailList initiator, emails
        emails.push initiator

        UsersFromEmails emails, (err, users) ->
          googleAuth.getCalendarsFromUsers users, (cals) ->
            calendarParser = new CalendarParser(timezone, lenInMin)
            availability = calendarParser.buildMeetingCalendar(cals)
            response = {}
            response.tandem_users = ({name: user.name, email: user.email} for user in users)
            response.schedule = availability
            res.status(200).send response

  addMeeting: (req, res) ->
    initiator = req.user
    req.body.meeting_initiator = initiator.email

    lenInMin = req.body.length_in_min

    User.methods.findByGoogleId initiator.id, (err, initiatorUser) ->
      googleAuth.getAuthClient initiatorUser, (oauth2Client) ->
        googleAuth.getUserTimezone oauth2Client, (timezoneSetting) ->
          timezone = timezoneSetting.value
          req.body.timezone = timezone
          Meeting.methods.create req.body, (meeting) ->
            emails = [req.user.email]
            if req.body.attendees
              emails = emails.concat (attendee.email for attendee in req.body.attendees)
            UsersFromEmails emails, (err, users) ->
              googleAuth.getCalendarsFromUsers users, (cals) ->
                calendarParser = new CalendarParser(timezone, lenInMin)
                availability = calendarParser.buildMeetingCalendar(cals)
                response = {}
                response.meeting_id = meeting._id
                response.tandem_users = ({name: user.name, email: user.email} for user in users)
                response.schedule = availability
                res.status(200).send response



  sendEmailInvites: (req, res) ->
    meeting_id = req.body.meeting_id
    meetingSummary = req.body.meeting_summary
    meetingLocation = req.body.meeting_location
    timeSelections = req.body.meeting_time_selection

    cursor = Meeting.methods.findById meeting_id
    user_id = req.user.id
    User.methods.findByGoogleId user_id, (err, user) ->
      googleAuth.getAuthClient user, (oauth2Client) ->
        cursor.on 'data', (doc) ->
          emailsArr = []
          for email in doc.emails
            toPush = {email}
            emailsArr.push toPush

          #randomly choose time slot
          slot = timeSelections[Math.floor(Math.random() * (timeSelections.length-1))]

          meetingInfo =
            meetingSummary: meetingSummary
            meetingLocation: meetingLocation
            meetingAttendees: emailsArr
            timeSlot: slot
          googleAuth.sendCalendarInvite oauth2Client, meetingInfo, (event) ->
            res.status(200).send(event)


# Private Helpers
UsersFromEmails = (emails, callback) ->
  #collect google Ids from user db from emails
  User.methods.findByEmailList emails, callback

inEmailList = (email, email_list) ->
  for e in email_list
    if email == e
      return true
  return false

module.exports = meetingController
