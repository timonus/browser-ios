(function() {
  var Command, Version,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Version = (function(_super) {
    __extends(Version, _super);

    function Version() {
      return Version.__super__.constructor.apply(this, arguments);
    }

    Version.prototype.name = 'version';

    Version.prototype.definition = 'Shows the current version or pry.js you are using.';

    Version.prototype.execute = function(args, chain) {
      var content;
      content = require('fs').readFileSync("" + __dirname + "/../../../package.json");
      this.output.send(JSON.parse(content)['version']);
      return chain.next();
    };

    return Version;

  })(Command);

  module.exports = Version;

}).call(this);
