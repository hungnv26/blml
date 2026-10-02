// Top bar of the full-size image/video viewer: download, share (where the browser can share files),
// and close. No file details: the viewer shows only the media.

import React from 'react';
import { defineMessages, injectIntl } from 'react-intl';

import { urlAsAttachment } from '../lib/utils.js';

const messages = defineMessages({
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

// Checks if the browser can share a file of the given type (Web Share API level 2).
function canShareFiles(mime) {
  try {
    return typeof navigator == 'object' && !!navigator.share && !!navigator.canShare &&
      navigator.canShare({files: [new File([''], 'media', {type: mime || 'application/octet-stream'})]});
  } catch (err) {
    return false;
  }
}

class MediaViewerActions extends React.PureComponent {
  constructor(props) {
    super(props);

    this.handleShare = this.handleShare.bind(this);
  }

  // Shares the file itself, never its URL: server URLs carry the user's auth token.
  handleShare(e) {
    e.preventDefault();
    fetch(this.props.url)
      .then(resp => {
        if (!resp.ok) {
          throw new Error(resp.statusText || ('HTTP ' + resp.status));
        }
        return resp.blob();
      })
      .then(blob => {
        const type = this.props.mime || blob.type;
        const file = new File([blob], this.props.filename || 'media', {type: type});
        return navigator.share({files: [file]});
      })
      .catch(err => {
        // AbortError: the user closed the share sheet.
        if (err && err.name != 'AbortError' && this.props.onError) {
          this.props.onError(err.message, 'err');
        }
      });
  }

  render() {
    const {formatMessage} = this.props.intl;
    const download = formatMessage(messages.download);
    const share = formatMessage(messages.share);
    const close = formatMessage(messages.close);
    return (
      <div id="preview-caption-panel" className="media-viewer-actions">
        <div>
          {this.props.url ?
            <a href={urlAsAttachment(this.props.url)} download={this.props.filename || ''}
              title={download} aria-label={download}>
              <i className="material-icons">file_download</i>
            </a> : null}
          {this.props.url && canShareFiles(this.props.mime) ?
            <a href="#" onClick={this.handleShare} title={share} aria-label={share}>
              <i className="material-icons">share</i>
            </a> : null}
        </div>
        <a href="#" onClick={e => {e.preventDefault(); this.props.onClose();}} title={close} aria-label={close}>
          <i className="material-icons gray">close</i>
        </a>
      </div>
    );
  }
}

export default injectIntl(MediaViewerActions);
