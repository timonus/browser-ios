(function() {
  var Command, Help, Range, chalk,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Range = require('../range');

  chalk = require('chalk');

  Help = (function(_super) {
    __extends(Help, _super);

    function Help() {
      return Help.__super__.constructor.apply(this, arguments);
    }

    Help.prototype.name = 'help';

    Help.prototype.aliases = ['\\?'];

    Help.prototype.definition = 'Shows a list of commands. Type `help foo` for help on the `foo` command.';

    Help.prototype.help = 'You just lost the game.';

    Help.prototype.args = new Range(0, 1);

    Help.prototype.typeahead = function(input) {
      var command, items, name, _ref;
      if (input == null) {
        input = '';
      }
      if (input.indexOf('help') === 0) {
        items = [];
        _ref = this.commands();
        for (name in _ref) {
          command = _ref[name];
          if (command.name) {
            items.push("help " + command.name);
          }
        }
        return items;
      } else {
        return ['help'];
      }
    };

    Help.prototype.execute = function(_arg, chain) {
      var command, name, _ref;
      name = _arg[0];
      if (name) {
        command = this.command(name);
        this.output.add(chalk.blue(command.name), '-', command.definition);
        this.output.add(command.help);
        this.output.sendAll();
      } else {
        _ref = this.commands();
        for (name in _ref) {
          command = _ref[name];
          if (command.name) {
            this.output.add(chalk.blue(command.name), '-', command.definition);
          }
        }
        this.output.sendAll();
      }
      return chain.next();
    };

    return Help;

  })(Command);

  module.exports = Help;

}).call(this);
