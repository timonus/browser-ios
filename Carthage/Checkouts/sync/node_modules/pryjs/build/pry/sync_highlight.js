(function() {
  var SyncHighlight, chalk, deasync, pygmentize, util;

  pygmentize = require('pygmentize-bundled');

  deasync = require('deasync');

  chalk = require('chalk');

  util = require('util');

  SyncHighlight = (function() {
    SyncHighlight.prototype.content = null;

    SyncHighlight.prototype.type = null;

    function SyncHighlight(obj, type) {
      this.type = type != null ? type : 'javascript';
      if (typeof obj === 'function') {
        this.content = obj.toString();
      } else if (typeof obj === 'string') {
        this.content = obj;
      } else {
        this.content = JSON.stringify(obj, this.stringify, "\t");
      }
    }

    SyncHighlight.prototype.stringify = function(key, value) {
      if (typeof value === 'function') {
        return util.inspect(value);
      }
      return value;
    };

    SyncHighlight.prototype.highlight = function() {
      var data, done;
      if (chalk.supportsColor) {
        done = data = false;
        pygmentize({
          lang: this.type,
          format: "terminal"
        }, this.content, (function(_this) {
          return function(err, res) {
            done = true;
            return data = res.toString();
          };
        })(this));
        while (!done) {
          deasync.runLoopOnce();
        }
      } else {
        data = this.content;
      }
      return data;
    };

    SyncHighlight.prototype.code_snippet = function(start, end, line_number, line_pointer) {
      var key, line, lines, pointer, _i, _len;
      if (line_pointer == null) {
        line_pointer = ' => ';
      }
      lines = this.highlight().split('\n');
      for (key = _i = 0, _len = lines.length; _i < _len; key = ++_i) {
        line = lines[key];
        if (key + 1 === line_number) {
          pointer = line_pointer;
        } else {
          pointer = this._spaces(line_pointer.length);
        }
        lines[key] = "" + pointer + (this._space(key + 1)) + (chalk.cyan(key + 1)) + ": " + line;
      }
      return lines.slice(start - 1, end).join('\n');
    };

    SyncHighlight.prototype._space = function(line) {
      return this._spaces(4 - String(line).length);
    };

    SyncHighlight.prototype._spaces = function(length, char) {
      if (char == null) {
        char = ' ';
      }
      return new Array(length + 1).join(char);
    };

    return SyncHighlight;

  })();

  module.exports = SyncHighlight;

}).call(this);
