import React from 'react';
import MediaViewerActions from './media-viewer-actions.jsx';
import SendMessage from './send-message.jsx';

import { REM_SIZE } from '../config.js';
import { fitImageSize } from '../lib/blob-helpers.js';
import { shortenFileName } from '../lib/strformat.js';

export default class ImagePreview extends React.PureComponent {
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

    const dim = fitImageSize(this.props.content.width, this.props.content.height,
      this.state.width, this.state.height, false);
    const size = dim ? { width: dim.dstWidth + 'px', height: dim.dstHeight + 'px' } :
      ((this.props.content.width > this.props.content.height) ? {width: '100%'} : {height: '100%'});
    size.maxWidth = '100%';
    size.maxHeight = '100%';

    // Average font aspect ratio is ~0.5; File name takes 1/3 of the viewport width.
    const maxlength = Math.max(((this.state.width / REM_SIZE / 1.5) | 0) - 2, 12);
    const fname = shortenFileName(this.props.content.filename, maxlength) || '-';

    return (
      <div id="image-preview" className={this.props.onSendMessage ? null : 'media-viewer'}>
        {this.props.onSendMessage ?
          // Preview before sending: show the name of the file being sent.
          <div id="preview-caption-panel">
            <span>{fname}</span>
            <a href="#" onClick={(e) => {e.preventDefault(); this.props.onClose();}}><i className="material-icons gray">close</i></a>
          </div>
          :
          // Full-size view of a received/sent image: only the image, download/share and close.
          <MediaViewerActions
            url={this.props.content.url}
            filename={this.props.content.filename}
            mime={this.props.content.type}
            onError={this.props.onError}
            onClose={this.props.onClose} />
        }
        <div id="image-preview-container" ref={node => this.assignWidth(node)}>
          <img src={this.props.content.url} style={size} className="image-preview" alt={this.props.content.filename} />
        </div>
        {this.props.onSendMessage ?
          <SendMessage
            messagePrompt="add_image_caption"
            acceptBlank={true}
            tinode={this.props.tinode}
            reply={this.props.reply}
            onCancelReply={this.props.onCancelReply}
            onSendMessage={this.handleSendImage}
            onError={this.props.onError} />
          : null}
      </div>
    );
  }
};
