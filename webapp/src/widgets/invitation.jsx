// A single topic or user.
import React from 'react';
import { FormattedMessage } from 'react-intl';

export default class Invitation extends React.PureComponent {
  constructor(props) {
    super(props);

    this.handleButtonAction = this.handleButtonAction.bind(this);
  }

  handleButtonAction(evt, data) {
    evt.preventDefault();
    this.props.onAction(data);
  }

  render() {
    return (
      <div className="accept-invite-panel">
        <div className="title">
          {this.props.p2p ?
            // 1:1 chat request (contract-friend-requests.md): nobody can write until it's accepted.
            (this.props.name ?
              <FormattedMessage id="chat_request_incoming"
                defaultMessage="{name} wants to chat with you. You can chat once you accept."
                description="1:1 chat request from another user: [Accept] [Decline] [Block]."
                values={{name: <b>{this.props.name}</b>}} />
              :
              <FormattedMessage id="chat_request_incoming_unnamed"
                defaultMessage="Someone wants to chat with you. You can chat once you accept."
                description="1:1 chat request from a user without a name: [Accept] [Decline] [Block]." />)
            :
            <FormattedMessage id="chat_invitation"
              defaultMessage="You are invited to start a new chat. What would you like to do?"
              description="New chat invitation message: [Accept] [Ignore] [Block]." />}
        </div>
        <div className="footer">
          <button className="primary" onClick={event => { this.handleButtonAction(event, "accept"); }}>
            <FormattedMessage id="chat_invitation_accept"
              defaultMessage="Accept" description="Action [Accept] for chat invitation." />
          </button>
          <button className="secondary" onClick={event => { this.handleButtonAction(event, "delete"); }}>
            {this.props.p2p ?
              <FormattedMessage id="chat_request_decline"
                defaultMessage="Decline" description="Action [Decline] for a 1:1 chat request." />
              :
              <FormattedMessage id="chat_invitation_ignore"
                defaultMessage="Ignore" description="Action [Ignore] for chat invitation." />}
          </button>
          <button className="secondary" onClick={event => { this.handleButtonAction(event, "block"); }}>
            <FormattedMessage id="chat_invitation_block"
              defaultMessage="Block" description="Action [Block] for chat invitation." />
          </button>
        </div>
      </div>
    );
  }
};
