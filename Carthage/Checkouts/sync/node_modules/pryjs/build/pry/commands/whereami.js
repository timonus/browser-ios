(function() {
  var Command, Range, Whereami,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Command = require('../command');

  Range = require('../range');

  Whereami = (function(_super) {
    __extends(Whereami, _super);

    Whereami.prototype.name = 'whereami';

    Whereami.prototype.definition = 'Shows you exactly where you are in the code.';

    Whereami.prototype.help = '`whereami` - Shows you where you are. \n`whereami 6` - Gives you 6 lines before instead of 5. \n`whereami 6 8` - Gives you 6 lines before instead of 5, and 8 lines after.';

    Whereami.prototype.args = new Range(0, 2);

    function Whereami() {
      Whereami.__super__.constructor.apply(this, arguments);
      this.file = this.find_file();
    }

    Whereami.prototype.execute = function(_arg, chain) {
      var after, before, end, start;
      before = _arg[0], after = _arg[1];
      before || (before = 5);
      after || (after = 5);
      start = this.file.line - parseInt(before, 10);
      end = this.file.line + parseInt(after, 10);
      this.output.send(this.file.formatted_content_by_line(start, end));
      return chain.next();
    };

    return Whereami;

  })(Command);

  module.exports = Whereami;

}).call(this);
