(function() {
  var Command, Compiler, Range, Xecute,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Range = require('../range');

  Compiler = require('../compiler');

  Xecute = (function(_super) {
    __extends(Xecute, _super);

    Xecute.prototype.name = 'mode';

    Xecute.prototype.definition = 'Switched between CoffeeScript and JavaScript execution.';

    Xecute.prototype.help = 'Type `mode` to switch between using JavaScript or CoffeeScript.';

    Xecute.prototype.last_error = null;

    Xecute.prototype.args = new Range(1, Infinity);

    function Xecute() {
      Xecute.__super__.constructor.apply(this, arguments);
      this.compiler = new Compiler({
        scope: this.scope
      });
    }

    Xecute.prototype.execute = function(input, chain) {
      if (input[0] === 'mode') {
        return this.switch_mode(chain);
      }
      this.execute_code(input.join(' '));
      return chain.next();
    };

    Xecute.prototype.execute_code = function(code, language) {
      var err;
      if (language == null) {
        language = null;
      }
      try {
        return this.output.send(this.compiler.execute(code, language));
      } catch (_error) {
        err = _error;
        this.last_error = err;
        return this.output.send(err);
      }
    };

    Xecute.prototype.switch_mode = function(chain) {
      this.compiler.toggle_mode();
      this.output.send("Switched mode to '" + (this.compiler.mode()) + "'.");
      return chain.next();
    };

    Xecute.prototype.match = function(input) {
      return [input, input];
    };

    return Xecute;

  })(Command);

  module.exports = Xecute;

}).call(this);
