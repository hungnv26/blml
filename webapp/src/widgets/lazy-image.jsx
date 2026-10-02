// Image with a placeholder which is replaced when the promise is resolved.
import React from 'react';

export default class LazyImage extends React.PureComponent {
  constructor(props) {
    super(props);

    this.state = {
      src: this.props.isvideo ? 'img/blankvid.png' : 'img/blankimg.png',
      style: Object.assign({padding: '4px'}, this.props.style),
      className: this.props.className,
      alt: this.props.alt,
      onClick: this.props.onClick,
    };
  }

  componentDidMount() {
    this.watch(this.props.whenDone);
  }

  watch(whenDone) {
    // whenDone is a wrapper around an actual promise to be able to cancel it.
    // Results of a promise which is no longer current are ignored.
    whenDone
      .promise
      .then(data => {
        if (whenDone === this.props.whenDone) {
          this.setState({src: data.src, style: {...this.state.style, padding: 0}});
        }
      })
      .catch(_ => {
        if (whenDone === this.props.whenDone) {
          this.setState({src: this.props.isvideo ? 'img/broken_video.png' : 'img/broken_image.png'});
        }
      });
  }

  componentWillUnmount() {
    this.props.whenDone.cancel();
  }

  componentDidUpdate(prevProps) {
    if (prevProps.whenDone !== this.props.whenDone) {
      prevProps.whenDone.cancel();
      this.setState({src: this.props.isvideo ? 'img/blankvid.png' : 'img/blankimg.png', style: {...this.state.style, padding: '4px'}});
      this.watch(this.props.whenDone);
    }
  }

  render() {
    return React.createElement('img', this.state);
  }
};
