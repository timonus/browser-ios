(function() {
  var EventEmitter, MultilineState, SinglelineState, SyncPrompt, deasync, readline, _,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  readline = require('readline');

  EventEmitter = require('events').EventEmitter;

  deasync = require('deasync');

  _ = require('underscore');

  MultilineState = (function() {
    function MultilineState() {}

    MultilineState.prototype.data = '';

    MultilineState.prototype.keypress = function(input, chars) {
      this.data += chars;
      if (this.data.match(/(\r|\n)\1$/)) {
        this.data = '';
        input.state('single');
        return input.send_data();
      } else if (chars.match(/(\r|\n)$/)) {
        return input.prompt();
      }
    };

    MultilineState.prototype.prompt = function(input, prompt) {
      if (this.data === '') {
        input.cli.setPrompt(prompt.replace(/[^>](?!$)/g, '-'));
      } else {
        input.cli.setPrompt(prompt.replace(/.(?!$)/g, '.'));
      }
      return input.cli.prompt();
    };

    return MultilineState;

  })();

  SinglelineState = (function() {
    function SinglelineState() {}

    SinglelineState.prototype.keypress = function(input, chars) {
      if (chars === '\u0016') {
        input.state('multi');
        return input.prompt();
      } else if (chars.match(/(\r|\n)$/)) {
        return input.send_data();
      }
    };

    SinglelineState.prototype.prompt = function(input, prompt) {
      input.cli.setPrompt(prompt);
      return input.cli.prompt();
    };

    return SinglelineState;

  })();

  SyncPrompt = (function(_super) {
    __extends(SyncPrompt, _super);

    SyncPrompt.prototype.lines = '';

    SyncPrompt.prototype.count = 0;

    SyncPrompt.prototype.states = {
      multi: new MultilineState,
      single: new SinglelineState
    };

    SyncPrompt.prototype._state = 'single';

    SyncPrompt.prototype.done = false;

    function SyncPrompt(options) {
      this.options = options != null ? options : {};
      this.close = __bind(this.close, this);
      this.type = __bind(this.type, this);
      this.prompt = __bind(this.prompt, this);
      this.send_data = __bind(this.send_data, this);
      this.keypress = __bind(this.keypress, this);
      this.line = __bind(this.line, this);
      this.state = __bind(this.state, this);
      this.options = _.extend(_.pick(process, 'stdin', 'stdout'), this.options);
      this.cli = readline.createInterface({
        input: this.options.stdin,
        output: this.options.stdout,
        completer: this.options.typeahead
      });
      this.cli.on('line', this.line);
      this.options.stdin.on('data', this.keypress);
    }

    SyncPrompt.prototype.state = function(state) {
      if (state) {
        this._state = state;
      }
      return this.states[this._state];
    };

    SyncPrompt.prototype.line = function(line) {
      if (line.charCodeAt(0) === 22) {
        line = line.slice(1);
      }
      return this.lines += '\n' + line;
    };

    SyncPrompt.prototype.keypress = function(chars) {
      return this.state().keypress(this, chars.toString());
    };

    SyncPrompt.prototype.send_data = function() {
      this.count++;
      this.emit('data', this.lines.trim(), {
        next: this.prompt,
        stop: this.close
      });
      return this.lines = '';
    };

    SyncPrompt.prototype.prompt = function() {
      return this.state().prompt(this, "[" + this.count + "] pryjs> ");
    };

    SyncPrompt.prototype.open = function() {
      var _results;
      this.done = false;
      this.prompt();
      _results = [];
      while (!this.done) {
        _results.push(deasync.runLoopOnce());
      }
      return _results;
    };

    SyncPrompt.prototype.type = function(input) {
      this.lines = input;
      return this.send_data();
    };

    SyncPrompt.prototype.close = function() {
      this.done = true;
      this.options.stdin.removeListener('data', this.keypress);
      return this.cli.close();
    };

    return SyncPrompt;

  })(EventEmitter);

  module.exports = SyncPrompt;

}).call(this);
