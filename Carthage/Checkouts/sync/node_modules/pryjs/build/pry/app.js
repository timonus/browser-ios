(function() {
  var App, Output, SyncPrompt, commands,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  SyncPrompt = require('./sync_prompt');

  Output = require('./output/local_output');

  commands = require('./commands');

  App = (function() {
    App.prototype._commands = [];

    function App(scope) {
      this.scope = scope;
      this.find_command = __bind(this.find_command, this);
      this.typeahead = __bind(this.typeahead, this);
      this.output = new Output();
      this.prompt = new SyncPrompt({
        typeahead: this.typeahead
      });
      this.prompt.on('data', this.find_command);
    }

    App.prototype.commands = function() {
      var command, i;
      if (this._commands.length === 0) {
        for (i in commands) {
          command = commands[i];
          this._commands.push(new command({
            output: this.output,
            scope: this.scope
          }));
        }
      }
      return this._commands;
    };

    App.prototype.typeahead = function(input) {
      var command, items, _i, _len, _ref;
      if (input == null) {
        input = '';
      }
      items = [];
      _ref = this.commands();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        command = _ref[_i];
        items = items.concat(command.typeahead(input));
      }
      if (input) {
        items = items.filter(function(item) {
          return item.indexOf(input) === 0;
        });
      }
      return [items, input];
    };

    App.prototype.find_command = function(input, chain) {
      var args, command, match, _i, _len, _ref;
      _ref = this.commands();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        command = _ref[_i];
        if (match = command.match(input.trim())) {
          args = String(match[1]).trim().split(' ');
          return command.execute.call(command, args, chain);
        }
      }
      return false;
    };

    App.prototype.open = function() {
      this.prompt.type('whereami');
      return this.prompt.open();
    };

    return App;

  })();

  module.exports = App;

}).call(this);
