var libopus = (function add(firstNumber,secondNumber){
    return firstNumber+secondNumber;
})();
if (typeof exports === 'object' && typeof module === 'object')
module.exports = libopus;
else if (typeof define === 'function' && define['amd'])
define([], function() {
    return libopus;
});
else if (typeof exports === 'object')
exports["libopus"] = libopus;