import React from 'react';
import { defineMessages, injectIntl } from 'react-intl';
import MediaViewerActions from './media-viewer-actions.jsx';
import SendMessage from './send-message.jsx';

const messages = defineMessages({
  unrecognized_video_format: {
    id: 'unrecognized_video_format',
    defaultMessage: 'Format of this video is not recognized',
    description: 'Error message when uploaded video is invalid',
  }
});

class VideoPreview extends React.PureComponent {
  constructor(props) {
    super(props);

    this.videoRef = React.createRef();

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
      duration: (this.videoRef.current.duration * 1000) | 0,
      mime: this.props.content.mime,
      name: this.props.content.filename
    }

    if (!params.width || !params.height) {
      this.props.onError(this.props.intl.formatMessage(messages.unrecognized_video_format), 'err');
      return;
    }

    // Capture screen from a video.
    const canvas = document.createElement('canvas');
    canvas.width = params.width;
    canvas.height = params.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(this.videoRef.current, 0, 0, canvas.width, canvas.height);
    ctx.canvas.toBlob(
        preview => this.props.onSendMessage(caption, this.props.content.blob, preview, params),
        'image/jpeg', 0.75
    );
  }

  render() {
    if (!this.props.content) {
      return null;
    }

    const controlist = this.props.onSendMessage ? 'nodownload' : '';
    const autoPlay = !this.props.onSendMessage;

    return (
      <div id="image-preview" className={this.props.onSendMessage ? null : 'media-viewer'}>
        {this.props.onSendMessage ?
          // Preview before sending: show the name of the file being sent.
          <div id="preview-caption-panel">
            <span>{this.props.content.filename}</span>
            <a href="#" onClick={e => {e.preventDefault(); this.props.onClose();}}><i className="material-icons gray">close</i></a>
          </div>
          :
          // Full-size player: only the video, download/share and close.
          <MediaViewerActions
            url={this.props.tinode.authorizeURL(this.props.content.url)}
            filename={this.props.content.filename}
            mime={this.props.content.type}
            onError={this.props.onError}
            onClose={this.props.onClose} />
        }
        <div id="image-preview-container">
          <video
            className="image-preview"
            controls controlsList={controlist}
            disablePictureInPicture playsInline ref={this.videoRef}
            autoPlay={autoPlay}
            src={this.props.tinode.authorizeURL(this.props.content.url)}
            poster={this.props.content.preview}
            alt={this.props.content.filename} />
        </div>
        {this.props.onSendMessage ?
        <SendMessage
          messagePrompt="add_image_caption"
          acceptBlank={true}
          tinode={this.props.tinode}
          reply={this.props.reply}
          onCancelReply={this.props.onCancelReply}
          onSendMessage={this.handleSendVideo}
          onError={this.props.onError} />
          : null}
      </div>
    );
  }
};

export default injectIntl(VideoPreview);
