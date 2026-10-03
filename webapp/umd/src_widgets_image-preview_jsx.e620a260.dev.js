"use strict";
(self["webpackChunktinode_webapp"] = self["webpackChunktinode_webapp"] || []).push([["src_widgets_image-preview_jsx"],{

/***/ "./src/widgets/image-preview.jsx":
/*!***************************************!*\
  !*** ./src/widgets/image-preview.jsx ***!
  \***************************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   "default": function() { return /* binding */ ImagePreview; }
/* harmony export */ });
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! react */ "react");
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(react__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var _media_viewer_actions_jsx__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! ./media-viewer-actions.jsx */ "./src/widgets/media-viewer-actions.jsx");
/* harmony import */ var _send_message_jsx__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! ./send-message.jsx */ "./src/widgets/send-message.jsx");
/* harmony import */ var _config_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(/*! ../config.js */ "./src/config.js");
/* harmony import */ var _lib_blob_helpers_js__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(/*! ../lib/blob-helpers.js */ "./src/lib/blob-helpers.js");
/* harmony import */ var _lib_strformat_js__WEBPACK_IMPORTED_MODULE_5__ = __webpack_require__(/*! ../lib/strformat.js */ "./src/lib/strformat.js");
/* harmony import */ var react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__ = __webpack_require__(/*! react/jsx-dev-runtime */ "./node_modules/react/jsx-dev-runtime.js");







class ImagePreview extends (react__WEBPACK_IMPORTED_MODULE_0___default().PureComponent) {
  constructor(props) {
    super(props);
    this.state = {
      width: 0,
      height: 0
    };
    this.handleSendImage = this.handleSendImage.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
  }
  componentDidMount() {
    document.addEventListener('keydown', this.handleKeyDown);
  }
  componentWillUnmount() {
    document.removeEventListener('keydown', this.handleKeyDown);
  }
  handleKeyDown(e) {
    if (this.props.onSendMessage) {
      return;
    }
    e.preventDefault();
    if (e.key === 'Escape') {
      this.props.onClose();
    }
  }
  assignWidth(node) {
    if (node && !this.state.width) {
      const bounds = node.getBoundingClientRect();
      this.setState({
        width: bounds.width | 0,
        height: bounds.height | 0
      });
    }
  }
  handleSendImage(caption) {
    this.props.onClose();
    this.props.onSendMessage(caption, this.props.content.blob);
  }
  render() {
    if (!this.props.content) {
      return null;
    }
    const dim = (0,_lib_blob_helpers_js__WEBPACK_IMPORTED_MODULE_4__.fitImageSize)(this.props.content.width, this.props.content.height, this.state.width, this.state.height, false);
    const size = dim ? {
      width: dim.dstWidth + 'px',
      height: dim.dstHeight + 'px'
    } : this.props.content.width > this.props.content.height ? {
      width: '100%'
    } : {
      height: '100%'
    };
    size.maxWidth = '100%';
    size.maxHeight = '100%';
    const maxlength = Math.max((this.state.width / _config_js__WEBPACK_IMPORTED_MODULE_3__.REM_SIZE / 1.5 | 0) - 2, 12);
    const fname = (0,_lib_strformat_js__WEBPACK_IMPORTED_MODULE_5__.shortenFileName)(this.props.content.filename, maxlength) || '-';
    return (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("div", {
      id: "image-preview",
      className: this.props.onSendMessage ? null : 'media-viewer',
      children: [this.props.onSendMessage ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("div", {
        id: "preview-caption-panel",
        children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("span", {
          children: fname
        }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("a", {
          href: "#",
          onClick: e => {
            e.preventDefault();
            this.props.onClose();
          },
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("i", {
            className: "material-icons gray",
            children: "close"
          }, void 0, false)
        }, void 0, false)]
      }, void 0, true) : (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)(_media_viewer_actions_jsx__WEBPACK_IMPORTED_MODULE_1__["default"], {
        url: this.props.content.url,
        filename: this.props.content.filename,
        mime: this.props.content.type,
        onError: this.props.onError,
        onClose: this.props.onClose
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("div", {
        id: "image-preview-container",
        ref: node => this.assignWidth(node),
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)("img", {
          src: this.props.content.url,
          style: size,
          className: "image-preview",
          alt: this.props.content.filename
        }, void 0, false)
      }, void 0, false), this.props.onSendMessage ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_6__.jsxDEV)(_send_message_jsx__WEBPACK_IMPORTED_MODULE_2__["default"], {
        messagePrompt: "add_image_caption",
        acceptBlank: true,
        tinode: this.props.tinode,
        reply: this.props.reply,
        onCancelReply: this.props.onCancelReply,
        onSendMessage: this.handleSendImage,
        onError: this.props.onError
      }, void 0, false) : null]
    }, void 0, true);
  }
}
;

/***/ }),

/***/ "./src/widgets/media-viewer-actions.jsx":
/*!**********************************************!*\
  !*** ./src/widgets/media-viewer-actions.jsx ***!
  \**********************************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! react */ "react");
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(react__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! react-intl */ "react-intl");
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1___default = /*#__PURE__*/__webpack_require__.n(react_intl__WEBPACK_IMPORTED_MODULE_1__);
/* harmony import */ var _lib_utils_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! ../lib/utils.js */ "./src/lib/utils.js");
/* harmony import */ var react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(/*! react/jsx-dev-runtime */ "./node_modules/react/jsx-dev-runtime.js");




const messages = (0,react_intl__WEBPACK_IMPORTED_MODULE_1__.defineMessages)({
  download: {
    id: 'download_action',
    defaultMessage: 'download',
    description: 'Call to action [download]'
  },
  share: {
    id: 'share_action',
    defaultMessage: 'Share',
    description: 'Call to action [share] an image or a video from the full-size viewer'
  },
  close: {
    id: 'close_viewer_action',
    defaultMessage: 'Close',
    description: 'Call to action [close] the full-size image or video viewer'
  }
});
function canShareFiles(mime) {
  try {
    return typeof navigator == 'object' && !!navigator.share && !!navigator.canShare && navigator.canShare({
      files: [new File([''], 'media', {
        type: mime || 'application/octet-stream'
      })]
    });
  } catch (err) {
    return false;
  }
}
class MediaViewerActions extends (react__WEBPACK_IMPORTED_MODULE_0___default().PureComponent) {
  constructor(props) {
    super(props);
    this.handleShare = this.handleShare.bind(this);
  }
  handleShare(e) {
    e.preventDefault();
    fetch(this.props.url).then(resp => {
      if (!resp.ok) {
        throw new Error(resp.statusText || 'HTTP ' + resp.status);
      }
      return resp.blob();
    }).then(blob => {
      const type = this.props.mime || blob.type;
      const file = new File([blob], this.props.filename || 'media', {
        type: type
      });
      return navigator.share({
        files: [file]
      });
    }).catch(err => {
      if (err && err.name != 'AbortError' && this.props.onError) {
        this.props.onError(err.message, 'err');
      }
    });
  }
  render() {
    const {
      formatMessage
    } = this.props.intl;
    const download = formatMessage(messages.download);
    const share = formatMessage(messages.share);
    const close = formatMessage(messages.close);
    return (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("div", {
      id: "preview-caption-panel",
      className: "media-viewer-actions",
      children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("div", {
        children: [this.props.url ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("a", {
          href: (0,_lib_utils_js__WEBPACK_IMPORTED_MODULE_2__.urlAsAttachment)(this.props.url),
          download: this.props.filename || '',
          title: download,
          "aria-label": download,
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("i", {
            className: "material-icons",
            children: "file_download"
          }, void 0, false)
        }, void 0, false) : null, this.props.url && canShareFiles(this.props.mime) ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("a", {
          href: "#",
          onClick: this.handleShare,
          title: share,
          "aria-label": share,
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("i", {
            className: "material-icons",
            children: "share"
          }, void 0, false)
        }, void 0, false) : null]
      }, void 0, true), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("a", {
        href: "#",
        onClick: e => {
          e.preventDefault();
          this.props.onClose();
        },
        title: close,
        "aria-label": close,
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_3__.jsxDEV)("i", {
          className: "material-icons gray",
          children: "close"
        }, void 0, false)
      }, void 0, false)]
    }, void 0, true);
  }
}
/* harmony default export */ __webpack_exports__["default"] = ((0,react_intl__WEBPACK_IMPORTED_MODULE_1__.injectIntl)(MediaViewerActions));

/***/ })

}]);
//# sourceMappingURL=src_widgets_image-preview_jsx.e620a260.dev.js.map