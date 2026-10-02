// Editor for a phone number.

import React from 'react';
import { defineMessages, injectIntl } from 'react-intl';
import { AsYouType, getExampleNumber } from 'libphonenumber-js/mobile';
import examples from 'libphonenumber-js/mobile/examples'

import * as dcodes from '../dcodes.json';
import { asE164Phone, localRegions } from '../lib/phone';
import { flagEmoji } from '../lib/strformat';

const messages = defineMessages({
  phone_number_not_recognized: {
    id: 'phone_number_not_recognized',
    defaultMessage: 'This doesn\'t look like a phone number',
    description: 'Error message when the text entered in a phone number field is not a phone number'
  }
});

class PhoneEdit extends React.PureComponent {
  constructor(props) {
    super(props);

    this.codeMap = {};
    dcodes.default.forEach(dc => { this.codeMap[dc.code] = dc.dial; });

    // Country for numbers typed in local format: the given one, else the browser's region,
    // else the region of the user's own phone number (props.ownPhone, E.164).
    const code = [props.countryCode].concat(localRegions(
        typeof navigator == 'object' ? (navigator.languages || [navigator.language]) : [],
        props.ownPhone ? [props.ownPhone] : [])).find(c => c && this.codeMap[c]) || 'US';
    const dial = this.codeMap[code];

    this.state = {
      countryCode: code,
      dialCode: dial,
      localNumber: '',
      placeholderNumber: this.placeholderNumber(code)
    };

    this.handleChange = this.handleChange.bind(this);
    this.handleFinished = this.handleFinished.bind(this);
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.showCountrySelector = this.showCountrySelector.bind(this);
  }

  // Accepts the number in local format for the selected country ('0491 570 104') or in international
  // format ('+61 491 570 104'), with spaces, dashes, dots or brackets.
  handleChange(e) {
    const value = this.filterNumber(e.target.value);
    let formatted = value;
    const newState = {};
    if (value.startsWith('+')) {
      // International format: follow the country of the number.
      const typer = new AsYouType();
      formatted = typer.input(value);
      const code = typer.getCountry();
      if (code && code != this.state.countryCode && this.codeMap[code]) {
        Object.assign(newState, {
          countryCode: code,
          dialCode: this.codeMap[code],
          placeholderNumber: this.placeholderNumber(code)
        });
      }
    } else if (value.trim()) {
      formatted = new AsYouType(this.state.countryCode).input(value);
    }
    // Don't reformat what the user is deleting into, e.g. a trailing ')' or '-'.
    if (formatted.length < value.length) {
      formatted = value;
    }
    newState.localNumber = formatted;
    this.setState(newState);
    if (this.inputField) {
      this.inputField.setCustomValidity('');
    }
  }

  handleFinished(e) {
    e.preventDefault();
    const text = this.state.localNumber.trim();
    // Any possible number, not only a valid mobile one; sent as E.164.
    const e164 = text ? asE164Phone(text, [this.state.countryCode]) : null;
    if (!e164) {
      this.inputField.setCustomValidity(text ?
        this.props.intl.formatMessage(messages.phone_number_not_recognized) : '');
      if (text && e.type == 'keydown') {
        this.inputField.reportValidity();
      }
      // Don't leave an earlier number in the form.
      this.props.onSubmit('');
      return;
    }

    this.inputField.setCustomValidity('');
    // The number is in E.164; the selected country goes along as the server's params.region hint.
    this.props.onSubmit(e164, this.state.countryCode);
  }


  handleKeyDown(e) {
    if (e.key === 'Enter') {
      this.handleFinished(e);
    }
  }

  showCountrySelector() {
    this.props.onShowCountrySelector(this.state.countryCode, this.state.dialCode,
      (code, dial) => {
          this.setState({
            countryCode: code,
            dialCode: dial,
            placeholderNumber: this.placeholderNumber(code)
        })
      });
  }

  // Filter out characters not permitted in a phone number.
  filterNumber(number) {
    if (!number) {
      return number;
    }
    // Leave numbers, space, (, ), -, and . A leading + starts a number in international format.
    const plus = /^\s*\+/.test(number);
    return (plus ? '+' : '') + number.replace(/[^-\s().\d]/g, '').replace(/^\s+/, '');
  }

  // Example number in local format, e.g. '0412 345 678' for AU.
  placeholderNumber(code) {
    let sample = null;
    try {
      sample = getExampleNumber(code, examples);
    } catch (err) {}
    return sample ? sample.formatNational() : '123 0123';
  }

  render() {
    return (
      <>
        <span className="dial-code" onClick={this.showCountrySelector}>
          <span className="country-flag">{flagEmoji(this.state.countryCode)}&nbsp;</span>
          +{this.state.dialCode}&nbsp;</span>
        <input type="tel" ref={ref => {this.inputField = ref}} placeholder={this.state.placeholderNumber}
            value={this.state.localNumber} onChange={this.handleChange}
            maxLength={24} onKeyDown={this.handleKeyDown} onBlur={this.handleFinished}
            required autoFocus={this.props.autoFocus} />
      </>
    );
  }
}

export default injectIntl(PhoneEdit);
