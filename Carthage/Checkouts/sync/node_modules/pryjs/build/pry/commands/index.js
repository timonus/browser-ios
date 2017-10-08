(function() {
  var file, fs, name, _i, _len, _ref;

  fs = require('fs');

  _ref = fs.readdirSync(__dirname);
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    file = _ref[_i];
    if (file.match(/\.(coffee|js)$/) && !file.match(/index\.(js|coffee)/)) {
      file = file.substr(0, file.indexOf('.'));
      name = file.substring(0, 1).toUpperCase() + file.substring(1);
      exports[name] = require("./" + file);
    }
  }

}).call(this);
