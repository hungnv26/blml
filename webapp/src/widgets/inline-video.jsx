// Video inside a message bubble: a static preview (poster image with duration and a play button)
// which turns into an inline player when clicked. The player has a button to open the
// full-size viewer.

import React from 'react';
import { defineMessages, injectIntl } from 'react-intl';

import { secondsToTime } from '../lib/strformat.js'

const messages = defineMessages({
  expand: {
    id: 'video_full_size_action',
    defaultMessage: 'Full size',
    description: 'Call to action [open video in the full-size viewer]'
  }
});

class InlineVideo extends React.PureComponent {
  constructor(props) {
    super(props);

    this.state = {
      playing: false
    };

    this.videoRef = React.createRef();

    this.handlePlay = this.handlePlay.bind(this);
    this.handleExpand = this.handleExpand.bind(this);
  }

  handlePlay(e) {
    e.preventDefault();
    e.stopPropagation();
    this.setState({playing: true});
  }

  handleExpand(e) {
    if (this.videoRef.current) {
      this.videoRef.current.pause();
    }
    this.props.onExpand(e);
  }

  render() {
    // videoSrc: authorized URL of the video; onExpand: open the full-size viewer.
    // Everything else is for the <img> preview.
    const {videoSrc, onExpand, intl, ...imgProps} = this.props;
    // data-* attributes describe the video; the full-size viewer reads them from the clicked element.
    const dataAttrs = {};
    Object.keys(imgProps).forEach(key => {
      if (key.startsWith('data-')) {
        dataAttrs[key] = imgProps[key];
      }
    });

    if (this.state.playing && videoSrc) {
      const expand = intl.formatMessage(messages.expand);
      return (
        <div className="inline-video playing">
          <video ref={this.videoRef}
            className={imgProps.className}
            style={imgProps.style}
            src={videoSrc}
            poster={imgProps.src || undefined}
            preload={imgProps['data-preload'] || 'metadata'}
            controls autoPlay playsInline disablePictureInPicture />
          {onExpand ?
            <a href="#" className="expand-control" title={expand} aria-label={expand}
              onClick={this.handleExpand} {...dataAttrs}>
              <i className="material-icons white">open_in_full</i>
            </a> : null}
        </div>
      );
    }

    const playable = !!(videoSrc || imgProps.onClick);
    if (videoSrc) {
      imgProps.onClick = this.handlePlay;
    }
    const duration = secondsToTime(this.props['data-duration'] / 1000);
    const className = 'inline-video' + (playable ? ' image-clickable' : '');
    return (
      <div className={className}>
        {React.createElement('img', imgProps)}
        <div className="play-control">
        {playable ?
          <i className="material-icons white x-big">play_arrow</i>
          :
          <img src="img/broken_video.png" style={{filter: 'invert(100%)'}} width="36" height="36" />}
        </div>
        {duration ? <div className="duration">{duration}</div> : null}
      </div>
    );
  }
};

export default injectIntl(InlineVideo);
