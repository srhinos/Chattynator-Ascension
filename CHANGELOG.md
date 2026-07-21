# Chattynator

## [v1.0.4](https://github.com/srhinos/Chattynator-Ascension/tree/v1.0.4) (2026-07-19)
[Full Changelog](https://github.com/srhinos/Chattynator-Ascension/compare/v1.0.3...v1.0.4) [Previous Releases](https://github.com/srhinos/Chattynator-Ascension/releases)

- Fix Editbox Parent Anchor (but fr this time) and Fix ChatEdit\_GetChannelTarget crash (#6)  
    * Use the stock 3.3.5 channelTarget attribute instead of the nonexistent ChatEdit\_GetChannelTarget  
    * Re-assert the edit box parent on chat activate and zone change instead of OnShow  