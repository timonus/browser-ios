(function() {
  var Command, Play, Range,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Range = require('../range');

  Play = (function(_super) {
    __extends(Play, _super);

    Play.prototype.name = 'play';

    Play.prototype.definition = 'Play a specific line, or set of lines in the file you are in.';

    Play.prototype.help = '`play 1 2` will play lines 1 and 2.\n`play 1` will just play line 1.';

    Play.prototype.args = new Range(1, 2);

    function Play() {
      Play.__super__.constructor.apply(this, arguments);
      this.file = this.find_file();
    }

    Play.prototype.execute = function(_arg, chain) {
      var end, start;
      start = _arg[0], end = _arg[1];
      end || (end = start);
      this.command('xecute').execute_code(this.file.by_lines(start, end), this.file.type());
      return chain.next();
    };

    return Play;

  })(Command);

  module.exports = Play;

}).call(this);
