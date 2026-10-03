"use strict";
(self["webpackChunktinode_webapp"] = self["webpackChunktinode_webapp"] || []).push([["src_views_settings-view_jsx"],{

/***/ "./src/views/settings-view.jsx":
/*!*************************************!*\
  !*** ./src/views/settings-view.jsx ***!
  \*************************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   "default": function() { return /* binding */ SettingsView; }
/* harmony export */ });
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! react */ "react");
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(react__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! react-intl */ "react-intl");
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1___default = /*#__PURE__*/__webpack_require__.n(react_intl__WEBPACK_IMPORTED_MODULE_1__);
/* harmony import */ var _widgets_checkbox_jsx__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! ../widgets/checkbox.jsx */ "./src/widgets/checkbox.jsx");
/* harmony import */ var _widgets_host_selector_jsx__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(/*! ../widgets/host-selector.jsx */ "./src/widgets/host-selector.jsx");
/* harmony import */ var react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(/*! react/jsx-dev-runtime */ "./node_modules/react/jsx-dev-runtime.js");





class SettingsView extends (react__WEBPACK_IMPORTED_MODULE_0___default().PureComponent) {
  constructor(props) {
    super(props);
    this.state = {
      transport: props.transport || 'def',
      serverAddress: props.serverAddress,
      secureConnection: props.secureConnection
    };
    this.handleSubmit = this.handleSubmit.bind(this);
    this.handleTransportSelected = this.handleTransportSelected.bind(this);
    this.handleServerAddressChange = this.handleServerAddressChange.bind(this);
    this.handleToggleSecure = this.handleToggleSecure.bind(this);
  }
  handleSubmit(e) {
    e.preventDefault();
    this.props.onUpdate({
      transport: this.state.transport,
      serverAddress: this.state.serverAddress,
      secureConnection: this.state.secureConnection
    });
  }
  handleTransportSelected(e) {
    this.setState({
      transport: e.currentTarget.value
    });
  }
  handleServerAddressChange(name) {
    this.setState({
      serverAddress: name
    });
  }
  handleToggleSecure(e) {
    this.setState({
      secureConnection: !this.state.secureConnection
    });
  }
  render() {
    const names = {
      def: "default",
      ws: "websocket",
      lp: "long polling"
    };
    const transportOptions = [];
    ['def', 'ws', 'lp'].forEach(item => {
      const id = 'transport-' + item;
      const name = names[item];
      transportOptions.push((0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("li", {
        children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("input", {
          type: "radio",
          id: id,
          name: "transport-select",
          value: item,
          checked: this.state.transport === item,
          onChange: this.handleTransportSelected
        }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("label", {
          htmlFor: id,
          children: name
        }, void 0, false)]
      }, item, true));
    });
    return (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("form", {
      id: "settings-form",
      className: "panel-form",
      onSubmit: this.handleSubmit,
      children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        className: "panel-form-row",
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("label", {
          className: "small",
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(react_intl__WEBPACK_IMPORTED_MODULE_1__.FormattedMessage, {
            id: "label_server_to_use",
            defaultMessage: "Server to use:",
            description: "Label for server selector in SettingsView"
          }, void 0, false)
        }, void 0, false)
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(_widgets_host_selector_jsx__WEBPACK_IMPORTED_MODULE_3__["default"], {
        serverAddress: this.state.serverAddress,
        onServerAddressChange: this.handleServerAddressChange
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        className: "panel-form-row",
        children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(_widgets_checkbox_jsx__WEBPACK_IMPORTED_MODULE_2__["default"], {
          id: "secure-connection",
          name: "secure-connection",
          checked: this.state.secureConnection,
          className: "quoted",
          onChange: this.handleToggleSecure
        }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("label", {
          htmlFor: "secure-connection",
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(react_intl__WEBPACK_IMPORTED_MODULE_1__.FormattedMessage, {
            id: "label_use_secure_connection",
            defaultMessage: "Use secure connection",
            description: "Label for WS/WSS connection type in SettingsView"
          }, void 0, false)
        }, void 0, false)]
      }, void 0, true), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        className: "panel-form-row",
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("label", {
          className: "small",
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(react_intl__WEBPACK_IMPORTED_MODULE_1__.FormattedMessage, {
            id: "label_wire_transport",
            defaultMessage: "Wire transport:",
            description: "Label for wire transport selection in SettingsView"
          }, void 0, false)
        }, void 0, false)
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        className: "panel-form-row",
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("ul", {
          className: "quoted",
          children: transportOptions
        }, void 0, false)
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        className: "dialog-buttons",
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("button", {
          type: "submit",
          className: "primary",
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(react_intl__WEBPACK_IMPORTED_MODULE_1__.FormattedMessage, {
            id: "button_update",
            defaultMessage: "Update",
            description: "Button [Update]"
          }, void 0, false)
        }, void 0, false)
      }, void 0, false)]
    }, void 0, true);
  }
}
;

/***/ }),

/***/ "./src/widgets/host-selector.jsx":
/*!***************************************!*\
  !*** ./src/widgets/host-selector.jsx ***!
  \***************************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   "default": function() { return /* binding */ HostSelector; }
/* harmony export */ });
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! react */ "react");
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(react__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var _config_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ../config.js */ "./src/config.js");
/* harmony import */ var react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! react/jsx-dev-runtime */ "./node_modules/react/jsx-dev-runtime.js");



class HostSelector extends (react__WEBPACK_IMPORTED_MODULE_0___default().PureComponent) {
  constructor(props) {
    super(props);
    this.state = {
      hostName: props.serverAddress,
      changed: false
    };
    this.handleHostNameChange = this.handleHostNameChange.bind(this);
    this.handleEditingFinished = this.handleEditingFinished.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
  }
  handleHostNameChange(e) {
    this.setState({
      hostName: e.target.value,
      changed: true
    });
  }
  handleEditingFinished() {
    if (this.state.changed) {
      this.setState({
        changed: false
      });
      this.props.onServerAddressChange(this.state.hostName.trim());
    }
  }
  handleKeyDown(e) {
    if (e.key == 'Enter') {
      this.handleEditingFinished();
    }
  }
  render() {
    const hostOptions = [];
    for (let key in _config_js__WEBPACK_IMPORTED_MODULE_1__.KNOWN_HOSTS) {
      let item = _config_js__WEBPACK_IMPORTED_MODULE_1__.KNOWN_HOSTS[key];
      hostOptions.push((0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_2__.jsxDEV)("option", {
        value: item
      }, item, false));
    }
    return (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_2__.jsxDEV)("div", {
      className: "panel-form-row",
      children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_2__.jsxDEV)("input", {
        type: "search",
        id: "host-name",
        placeholder: this.props.hostName,
        list: "known-hosts",
        className: "quoted",
        value: this.state.hostName,
        onChange: this.handleHostNameChange,
        onBlur: this.handleEditingFinished,
        onKeyDown: this.handleKeyDown,
        required: true
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_2__.jsxDEV)("datalist", {
        id: "known-hosts",
        children: hostOptions
      }, void 0, false)]
    }, void 0, true);
  }
}

/***/ })

}]);
//# sourceMappingURL=src_views_settings-view_jsx.eefd4694.dev.js.map