"use strict";
(self["webpackChunktinode_webapp"] = self["webpackChunktinode_webapp"] || []).push([["src_lib_phone_js"],{

/***/ "./src/lib/phone.js":
/*!**************************!*\
  !*** ./src/lib/phone.js ***!
  \**************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   asE164Phone: function() { return /* binding */ asE164Phone; },
/* harmony export */   localRegions: function() { return /* binding */ localRegions; },
/* harmony export */   phoneRegion: function() { return /* binding */ phoneRegion; },
/* harmony export */   regionsFromLanguages: function() { return /* binding */ regionsFromLanguages; }
/* harmony export */ });
/* harmony import */ var libphonenumber_js_mobile__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! libphonenumber-js/mobile */ "./node_modules/libphonenumber-js/mobile/exports/parsePhoneNumber.js");

const MIN_PHONE_DIGITS = 6;
const MAX_PHONE_DIGITS = 15;
function regionsFromLanguages(languages) {
  const regions = [];
  (languages || []).forEach(lang => {
    const m = /[-_]([a-z]{2})(?:[-_]|$)/i.exec(lang || '');
    const region = m ? m[1].toUpperCase() : null;
    if (region && !regions.includes(region)) {
      regions.push(region);
    }
  });
  return regions;
}
function phoneRegion(e164) {
  const number = e164 ? (0,libphonenumber_js_mobile__WEBPACK_IMPORTED_MODULE_0__.parsePhoneNumber)(e164) : null;
  return number && number.country || null;
}
function localRegions(languages, ownPhones) {
  const regions = regionsFromLanguages(languages);
  (ownPhones || []).forEach(e164 => {
    const region = phoneRegion(e164);
    if (region && !regions.includes(region)) {
      regions.push(region);
    }
  });
  return regions;
}
function asE164Phone(val, regions) {
  val = (val || '').trim();
  if (!/^\+?[\d\s().\-\/]+$/.test(val)) {
    return null;
  }
  const digits = val.replace(/\D/g, '');
  if (digits.length < MIN_PHONE_DIGITS || digits.length > MAX_PHONE_DIGITS + 2) {
    return null;
  }
  const parse = (text, region) => {
    try {
      const number = (0,libphonenumber_js_mobile__WEBPACK_IMPORTED_MODULE_0__.parsePhoneNumber)(text, region);
      if (number && number.number.replace(/\D/g, '').length <= MAX_PHONE_DIGITS) {
        return number;
      }
    } catch (err) {}
    return null;
  };
  const international = text => {
    const number = parse(text);
    return number && (number.isValid() || number.isPossible()) ? number.number : null;
  };
  if (val.startsWith('+')) {
    return international('+' + digits);
  }
  const candidates = (regions || []).map(region => parse(val, region)).filter(number => number);
  const valid = candidates.find(number => number.isValid());
  if (valid) {
    return valid.number;
  }
  const idd = /^00[1-9]/.test(digits) ? international('+' + digits.substring(2)) : null;
  if (idd) {
    return idd;
  }
  const possible = candidates.find(number => number.isPossible());
  return possible ? possible.number : null;
}

/***/ }),

/***/ "./node_modules/libphonenumber-js/es6/parsePhoneNumber.js":
/*!****************************************************************!*\
  !*** ./node_modules/libphonenumber-js/es6/parsePhoneNumber.js ***!
  \****************************************************************/
/***/ (function(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   "default": function() { return /* binding */ parsePhoneNumber; }
/* harmony export */ });
/* harmony import */ var _normalizeArguments_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! ./normalizeArguments.js */ "./node_modules/libphonenumber-js/es6/normalizeArguments.js");
/* harmony import */ var _parsePhoneNumber_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ./parsePhoneNumber_.js */ "./node_modules/libphonenumber-js/es6/parsePhoneNumber_.js");


function parsePhoneNumber() {
  var _normalizeArguments = (0,_normalizeArguments_js__WEBPACK_IMPORTED_MODULE_0__["default"])(arguments),
    text = _normalizeArguments.text,
    options = _normalizeArguments.options,
    metadata = _normalizeArguments.metadata;
  return (0,_parsePhoneNumber_js__WEBPACK_IMPORTED_MODULE_1__["default"])(text, options, metadata);
}
//# sourceMappingURL=parsePhoneNumber.js.map

/***/ }),

/***/ "./node_modules/libphonenumber-js/es6/parsePhoneNumber_.js":
/*!*****************************************************************!*\
  !*** ./node_modules/libphonenumber-js/es6/parsePhoneNumber_.js ***!
  \*****************************************************************/
/***/ (function(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   "default": function() { return /* binding */ parsePhoneNumber; }
/* harmony export */ });
/* harmony import */ var _parsePhoneNumberWithError_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! ./parsePhoneNumberWithError_.js */ "./node_modules/libphonenumber-js/es6/parsePhoneNumberWithError_.js");
/* harmony import */ var _ParseError_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ./ParseError.js */ "./node_modules/libphonenumber-js/es6/ParseError.js");
/* harmony import */ var _metadata_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! ./metadata.js */ "./node_modules/libphonenumber-js/es6/metadata.js");
function _typeof(o) { "@babel/helpers - typeof"; return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (o) { return typeof o; } : function (o) { return o && "function" == typeof Symbol && o.constructor === Symbol && o !== Symbol.prototype ? "symbol" : typeof o; }, _typeof(o); }
function ownKeys(e, r) { var t = Object.keys(e); if (Object.getOwnPropertySymbols) { var o = Object.getOwnPropertySymbols(e); r && (o = o.filter(function (r) { return Object.getOwnPropertyDescriptor(e, r).enumerable; })), t.push.apply(t, o); } return t; }
function _objectSpread(e) { for (var r = 1; r < arguments.length; r++) { var t = null != arguments[r] ? arguments[r] : {}; r % 2 ? ownKeys(Object(t), !0).forEach(function (r) { _defineProperty(e, r, t[r]); }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function (r) { Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r)); }); } return e; }
function _defineProperty(e, r, t) { return (r = _toPropertyKey(r)) in e ? Object.defineProperty(e, r, { value: t, enumerable: !0, configurable: !0, writable: !0 }) : e[r] = t, e; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == _typeof(i) ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != _typeof(t) || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r || "default"); if ("object" != _typeof(i)) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }



function parsePhoneNumber(text, options, metadata) {
  // Validate `defaultCountry`.
  if (options && options.defaultCountry && !(0,_metadata_js__WEBPACK_IMPORTED_MODULE_2__.isSupportedCountry)(options.defaultCountry, metadata)) {
    options = _objectSpread(_objectSpread({}, options), {}, {
      defaultCountry: undefined
    });
  }
  // Parse phone number.
  try {
    return (0,_parsePhoneNumberWithError_js__WEBPACK_IMPORTED_MODULE_0__["default"])(text, options, metadata);
  } catch (error) {
    /* istanbul ignore else */
    if (error instanceof _ParseError_js__WEBPACK_IMPORTED_MODULE_1__["default"]) {
      //
    } else {
      throw error;
    }
  }
}
//# sourceMappingURL=parsePhoneNumber_.js.map

/***/ }),

/***/ "./node_modules/libphonenumber-js/mobile/exports/parsePhoneNumber.js":
/*!***************************************************************************!*\
  !*** ./node_modules/libphonenumber-js/mobile/exports/parsePhoneNumber.js ***!
  \***************************************************************************/
/***/ (function(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   parsePhoneNumber: function() { return /* binding */ parsePhoneNumber; }
/* harmony export */ });
/* harmony import */ var _withMetadataArgument_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! ./withMetadataArgument.js */ "./node_modules/libphonenumber-js/mobile/exports/withMetadataArgument.js");
/* harmony import */ var _core_index_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ../../core/index.js */ "./node_modules/libphonenumber-js/es6/parsePhoneNumber.js");



function parsePhoneNumber() {
	return (0,_withMetadataArgument_js__WEBPACK_IMPORTED_MODULE_0__["default"])(_core_index_js__WEBPACK_IMPORTED_MODULE_1__["default"], arguments)
}

/***/ })

}]);
//# sourceMappingURL=src_lib_phone_js.2915d77e.dev.js.map