'use strict'

exports = module.exports = (mongojs, db) ->
  User = db.collection('user')
  User.methods =

    findById: (id, callback) ->
      return User.find {
        _id: mongojs.ObjectId(id)
      }, (err, user) ->
        if err
          console.log "Find user by id error:", err
        if callback
          callback err, user

    findByGoogleId: (id, callback) ->
      return User.find {
        id: id
      }, (err, user) ->
        if err
          console.log "Find user by id error:", err
        if callback && user
          callback err, user[0]

    addUser: (user, callback)->
      db.collection('user').insert user, (err, result) ->
        if err
          console.log "Add User error", err
        if callback
          callback err, result

    update: (id, data, callback) ->
      return User.findAndModify {
        query: {_id: mongojs.ObjectId(id)}
        update: { $set: data }
        new: true
        }, (err, result) ->
          if err
            console.log "Update user error:", err
          if callback
            callback err, result

    findOne: (profileId, callback)->
      User.findOne profileId, (err, result) ->
        if err
          console.log "Find one user error:", err
        if callback
          callback err, result

    findByEmailList: (emails, callback) ->
      return User.find {
        email: {$in: emails}
      }, (err, users) ->
        if err
          console.log "Find user by email list error:", err
        if callback
          callback err, users

    updateAuth: (googleId, tokens, callback) ->
      return User.findAndModify {
        query: {id: googleId}
        update: { $set: { auth: tokens } }
      }, (err, result) ->
        if err || !result
          console.log "Update user auth error:", err
        if callback
          calback(err, result)

  return User

exports['@require'] = ['mongojs', 'database']