"use strict";
(self["webpackChunktinode_webapp"] = self["webpackChunktinode_webapp"] || []).push([["src_widgets_video-preview_jsx"],{

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

/***/ }),

/***/ "./src/widgets/video-preview.jsx":
/*!***************************************!*\
  !*** ./src/widgets/video-preview.jsx ***!
  \***************************************/
/***/ (function(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

__webpack_require__.r(__webpack_exports__);
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(/*! react */ "react");
/* harmony import */ var react__WEBPACK_IMPORTED_MODULE_0___default = /*#__PURE__*/__webpack_require__.n(react__WEBPACK_IMPORTED_MODULE_0__);
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(/*! react-intl */ "react-intl");
/* harmony import */ var react_intl__WEBPACK_IMPORTED_MODULE_1___default = /*#__PURE__*/__webpack_require__.n(react_intl__WEBPACK_IMPORTED_MODULE_1__);
/* harmony import */ var _media_viewer_actions_jsx__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(/*! ./media-viewer-actions.jsx */ "./src/widgets/media-viewer-actions.jsx");
/* harmony import */ var _send_message_jsx__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(/*! ./send-message.jsx */ "./src/widgets/send-message.jsx");
/* harmony import */ var react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(/*! react/jsx-dev-runtime */ "./node_modules/react/jsx-dev-runtime.js");





const messages = (0,react_intl__WEBPACK_IMPORTED_MODULE_1__.defineMessages)({
  unrecognized_video_format: {
    id: 'unrecognized_video_format',
    defaultMessage: 'Format of this video is not recognized',
    description: 'Error message when uploaded video is invalid'
  }
});
class VideoPreview extends (react__WEBPACK_IMPORTED_MODULE_0___default().PureComponent) {
  constructor(props) {
    super(props);
    this.videoRef = react__WEBPACK_IMPORTED_MODULE_0___default().createRef();
    this.handleSendVideo = this.handleSendVideo.bind(this);
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
  handleSendVideo(caption) {
    this.props.onClose();
    const params = {
      width: this.videoRef.current.videoWidth,
      height: this.videoRef.current.videoHeight,
      duration: this.videoRef.current.duration * 1000 | 0,
      mime: this.props.content.mime,
      name: this.props.content.filename
    };
    if (!params.width || !params.height) {
      this.props.onError(this.props.intl.formatMessage(messages.unrecognized_video_format), 'err');
      return;
    }
    const canvas = document.createElement('canvas');
    canvas.width = params.width;
    canvas.height = params.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(this.videoRef.current, 0, 0, canvas.width, canvas.height);
    ctx.canvas.toBlob(preview => this.props.onSendMessage(caption, this.props.content.blob, preview, params), 'image/jpeg', 0.75);
  }
  render() {
    if (!this.props.content) {
      return null;
    }
    const controlist = this.props.onSendMessage ? 'nodownload' : '';
    const autoPlay = !this.props.onSendMessage;
    return (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
      id: "image-preview",
      className: this.props.onSendMessage ? null : 'media-viewer',
      children: [this.props.onSendMessage ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        id: "preview-caption-panel",
        children: [(0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("span", {
          children: this.props.content.filename
        }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("a", {
          href: "#",
          onClick: e => {
            e.preventDefault();
            this.props.onClose();
          },
          children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("i", {
            className: "material-icons gray",
            children: "close"
          }, void 0, false)
        }, void 0, false)]
      }, void 0, true) : (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(_media_viewer_actions_jsx__WEBPACK_IMPORTED_MODULE_2__["default"], {
        url: this.props.tinode.authorizeURL(this.props.content.url),
        filename: this.props.content.filename,
        mime: this.props.content.type,
        onError: this.props.onError,
        onClose: this.props.onClose
      }, void 0, false), (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("div", {
        id: "image-preview-container",
        children: (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)("video", {
          className: "image-preview",
          controls: true,
          controlsList: controlist,
          disablePictureInPicture: true,
          playsInline: true,
          ref: this.videoRef,
          autoPlay: autoPlay,
          src: this.props.tinode.authorizeURL(this.props.content.url),
          poster: this.props.content.preview,
          alt: this.props.content.filename
        }, void 0, false)
      }, void 0, false), this.props.onSendMessage ? (0,react_jsx_dev_runtime__WEBPACK_IMPORTED_MODULE_4__.jsxDEV)(_send_message_jsx__WEBPACK_IMPORTED_MODULE_3__["default"], {
        messagePrompt: "add_image_caption",
        acceptBlank: true,
        tinode: this.props.tinode,
        reply: this.props.reply,
        onCancelReply: this.props.onCancelReply,
        onSendMessage: this.handleSendVideo,
        onError: this.props.onError
      }, void 0, false) : null]
    }, void 0, true);
  }
}
;
/* harmony default export */ __webpack_exports__["default"] = ((0,react_intl__WEBPACK_IMPORTED_MODULE_1__.injectIntl)(VideoPreview));

/***/ })

}]);
//# sourceMappingURL=src_widgets_video-preview_jsx.cee30469.dev.js.map