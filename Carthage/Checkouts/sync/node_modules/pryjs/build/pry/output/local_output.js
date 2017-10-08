(function() {
  var LocalOutput,
    __slice = [].slice;

  LocalOutput = (function() {
    function LocalOutput() {}

    LocalOutput.prototype.output = [];

    LocalOutput.prototype.send = function() {
      return console.log.apply(console.log, arguments);
    };

    LocalOutput.prototype.add = function() {
      var args;
      args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      return this.output.push(args.join(' '));
    };

    LocalOutput.prototype.sendAll = function() {
      this.send(this.output.join('\n'));
      return this.output = [];
    };

    return LocalOutput;

  })();

  module.exports = LocalOutput;

}).call(this);
