(function() {
  var Command, File, Range;

  File = require('./file');

  Range = require('./range');

  Command = (function() {
    Command.commands = {};

    Command.prototype.name = '';

    Command.prototype.aliases = [];

    Command.prototype.definition = '';

    Command.prototype.help = '';

    Command.prototype.args = new Range(0, 0);

    function Command(_arg) {
      this.scope = _arg.scope, this.output = _arg.output;
      this.stack = new Error().stack;
      this.constructor.commands[this.constructor.name] = this;
    }

    Command.prototype.command = function(input) {
      var command, name, _ref;
      _ref = this.commands();
      for (name in _ref) {
        command = _ref[name];
        if (command.constructor.name.match(new RegExp(input, 'i'))) {
          return command;
        }
      }
    };

    Command.prototype.commands = function() {
      return this.constructor.commands;
    };

    Command.prototype.typeahead = function() {
      var items;
      items = this.aliases.slice(0);
      items.push(this.name);
      return items;
    };

    Command.prototype.command_regex = function() {
      var subject;
      subject = "^(?:" + this.name;
      if (this.aliases.length > 0) {
        subject += "|" + (this.aliases.join('|'));
      }
      subject += ")((?: (?:[^ ]+))" + (this.args.to_regex()) + ")$";
      return new RegExp(subject);
    };

    Command.prototype.match = function(input) {
      return input.match(this.command_regex());
    };

    Command.prototype.find_file = function() {
      var file, foundCall, item, line, _, _i, _len, _ref, _ref1;
      foundCall = false;
      _ref = this.stack.split('\n');
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        item = _ref[_i];
        if (foundCall) {
          _ref1 = item.match(/([^ (:]+):(\d+):\d+/), _ = _ref1[0], file = _ref1[1], line = _ref1[2];
          if (file !== '<anonymous>') {
            return new File(file, line);
          }
        } else if (item.match(/Pry\.open/)) {
          foundCall = true;
        }
      }
      return new File(__filename, 1);
    };

    return Command;

  })();

  module.exports = Command;

}).call(this);
