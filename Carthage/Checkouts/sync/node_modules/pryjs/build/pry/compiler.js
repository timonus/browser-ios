(function() {
  var Compiler, coffee, pry;

  coffee = require('coffee-script');

  pry = require('../pry');

  Compiler = (function() {
    Compiler.prototype.mode_id = 0;

    Compiler.prototype.noVarPattern = /^\s*var .*$/gm;

    Compiler.prototype.modes = ['js', 'coffee'];

    function Compiler(_arg) {
      this.scope = _arg.scope;
    }

    Compiler.prototype.mode = function() {
      return this.modes[this.mode_id];
    };

    Compiler.prototype.toggle_mode = function() {
      return this.mode_id = (this.mode_id + 1) % this.modes.length;
    };

    Compiler.prototype.execute = function(code, language) {
      if (language == null) {
        language = this.modes[this.mode_id];
      }
      return this["execute_" + language](code);
    };

    Compiler.prototype.execute_coffee = function(code) {
      return this.execute_js(coffee.compile(code, {
        bare: true
      }).replace(this.noVarPattern, ''));
    };

    Compiler.prototype.execute_js = function(code) {
      return this.scope(code);
    };

    return Compiler;

  })();

  module.exports = Compiler;

}).call(this);
