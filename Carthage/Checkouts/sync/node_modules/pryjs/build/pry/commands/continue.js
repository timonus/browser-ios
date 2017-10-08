(function() {
  var Command, Continue,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Continue = (function(_super) {
    __extends(Continue, _super);

    function Continue() {
      return Continue.__super__.constructor.apply(this, arguments);
    }

    Continue.prototype.name = 'continue';

    Continue.prototype.aliases = ['exit', 'quit', 'stop'];

    Continue.prototype.definition = 'Ends the current prompt and continues running the rest of the code.';

    Continue.prototype.execute = function(args, chain) {
      return chain.stop();
    };

    return Continue;

  })(Command);

  module.exports = Continue;

}).call(this);
