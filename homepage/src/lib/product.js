export { default as appIcon } from '../../../docs/icon.svg';

export const repository = 'https://github.com/nickesc/cia-decrypter-ios';
export const releases = `${repository}/releases/latest`;
export const sourceURL = `${releases}/download/source.json`;
export const addSourceURL = `altstore://source?url=${encodeURIComponent(sourceURL)}`;
