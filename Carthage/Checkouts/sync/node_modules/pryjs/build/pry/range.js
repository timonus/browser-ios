(function() {
  var Range;

  Range = (function() {
    Range.prototype.start = 0;

    Range.prototype.end = 0;

    function Range(start, end) {
      this.start = start;
      this.end = end;
      if (this.start > this.end) {
        throw "Start must be smaller than end";
      }
    }

    Range.prototype.includes = function(i) {
      return this.start <= i && i <= this.end;
    };

    Range.prototype.to_regex = function() {
      if (this.end === Infinity) {
        return "{" + this.start + ",}";
      } else {
        return "{" + this.start + "," + this.end + "}";
      }
    };

    return Range;

  })();

  module.exports = Range;

}).call(this);
