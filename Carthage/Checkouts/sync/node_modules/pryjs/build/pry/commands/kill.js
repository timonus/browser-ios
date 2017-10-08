(function() {
  var Command, Kill,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Kill = (function(_super) {
    __extends(Kill, _super);

    function Kill() {
      return Kill.__super__.constructor.apply(this, arguments);
    }

    Kill.prototype.name = 'kill!';

    Kill.prototype.aliases = ['kill', 'exit!', 'quit!', 'stop!'];

    Kill.prototype.definition = 'Exits from the entire script.';

    Kill.prototype.execute = function(args, chain) {
      chain.stop();
      process.kill();
      return false;
    };

    return Kill;

  })(Command);

  module.exports = Kill;

}).call(this);
