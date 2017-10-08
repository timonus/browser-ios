(function() {
  var App, Pry;

  App = require('./pry/app');

  Pry = (function() {
    function Pry() {
      this.it = "(" + (this._pry.toString()) + ").call(this)";
    }

    Pry.prototype._pry = function() {
      var pry, _;
      pry = require('pryjs');
      _ = null;
      return pry.open((function(input) {
        return _ = eval(input);
      }).bind(this));
    };

    Pry.prototype.open = function(scope) {
      var app;
      app = new App(scope);
      return app.open();
    };

    return Pry;

  })();

  module.exports = new Pry;

}).call(this);
