import React from 'react';

import { SERVER_SETTINGS_ENABLED } from '../config.js';

export default class MenuStart extends React.PureComponent {
  render() {
    return (
        <div>
          <a href="#" onClick={(e) => {e.preventDefault(); this.props.onSignUp();}}><i className="material-icons">person_add</i></a>
          {SERVER_SETTINGS_ENABLED ? <>
            &nbsp;
            <a href="#" onClick={(e) => {e.preventDefault(); this.props.onSettings();}}><i className="material-icons">settings</i></a>
          </> : null}
        </div>
    );
  }
};
