config = require '../../config'
utils = require './utils'
{renderAccount, errorHandling, requireAuthenticate} = require './middleware'

mAccount = require '../model/account'
mSecurityLog = require '../model/security_log'

module.exports = exports = express.Router()

exports.get '/signup', renderAccount, (req, res) ->
  res.render 'account/signup'

exports.get '/login', renderAccount, (req, res) ->
  res.render 'account/login'

exports.get '/setting', requireAuthenticate, renderAccount, (req, res) ->
  res.render 'account/setting'

exports.post '/signup', errorHandling, (req, res) ->
  unless utils.rx.username.test req.body.username
    return res.error 'invalid_username'

  unless utils.rx.email.test req.body.email
    return res.error 'invalid_email'

  unless utils.rx.password.test req.body.password
    return res.error 'invalid_password'

  require('../../plugin/linux/monitor').loadPasswd (passwd_cache) ->
    if req.body.username in _.values(passwd_cache)
      return res.error 'username_exist'

    mAccount.byUsername req.body.username, (err, account) ->
      if account
        return res.error 'username_exist'

      mAccount.byEmail req.body.email, (err, account) ->
        if account
          return res.error 'email_exist'

        mAccount.register req.body.username, req.body.email, req.body.password, (err, account) ->
          mAccount.createToken account,
            ip: req.headers['x-real-ip']
            ua: req.headers['user-agent']
          , (err, token)->
            res.cookie 'token', token,
              expires: new Date(Date.now() + config.account.cookie_time)

            res.json
              id: account._id

exports.post '/login', errorHandling, (req, res) ->
  mAccount.byUsernameOrEmailOrId req.body.username, (err, account) ->
    unless account
      return res.error 'wrong_password'

    unless mAccount.matchPassword account, req.body.password
      return res.error 'wrong_password'

    mAccount.createToken account,
      ip: req.headers['x-real-ip']
      ua: req.headers['user-agent']
    , (err, token) ->
      res.cookie 'token', token,
        expires: new Date(Date.now() + config.account.cookie_time)

      res.json
        id: account._id
        token: token

exports.post '/logout', requireAuthenticate, (req, res) ->
  mAccount.removeToken req.token, ->
    res.clearCookie 'token'
    res.json {}

exports.post '/update_password', requireAuthenticate, (req, res) ->
  unless mAccount.matchPassword req.account, req.body.old_password
    return res.error 'wrong_password'

  unless utils.rx.password.test req.body.password
    return res.error 'invalid_password'

  mAccount.updatePassword req.account, req.body.password, ->
    token = _.first _.where req.account.tokens,
      token: req.token

    mSecurityLog.create req.account, 'update_password',
      token: _.omit(token, 'updated_at')
    , ->
      res.json {}
