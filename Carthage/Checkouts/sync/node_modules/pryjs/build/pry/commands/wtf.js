(function() {
  var Command, Wtf,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Wtf = (function(_super) {
    __extends(Wtf, _super);

    function Wtf() {
      return Wtf.__super__.constructor.apply(this, arguments);
    }

    Wtf.prototype.name = 'wtf';

    Wtf.prototype.definition = 'Shows the last caught exception.';

    Wtf.prototype.help = '`wtf` will show you the last caught exception.';

    Wtf.prototype.execute = function(args, chain) {
      if (this.command('xecute').last_error) {
        this.output.send(this.command('xecute').last_error.stack);
      } else {
        this.output.send('No errors');
      }
      return chain.next();
    };

    return Wtf;

  })(Command);

  module.exports = Wtf;

}).call(this);
