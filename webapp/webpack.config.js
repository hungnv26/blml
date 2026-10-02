const CopyPlugin = require('copy-webpack-plugin');
const path = require('path');

module.exports = (env, argv) => {
  const mode = argv.mode === 'production' ? 'prod' : 'dev';
  const maxAssetSize = mode === 'prod' ? 360000 : 1512000;
  return {
    entry: {
      index: path.resolve(__dirname, 'src/index.js'),
    },
    devtool: 'source-map',
    module: {
      rules: [
        {
          test: /\.jsx?$/,
          use: [
            {
              loader: 'babel-loader',
              options: {
                envName: mode === 'prod' ? 'production' : 'development',
              },
            },
          ],
          exclude: /node_modules/,
        },
      ],
    },
    output: {
      path: path.resolve(__dirname, 'umd'),
      filename: `[name].${mode}.js`,
      // Lazily loaded chunks get content-hashed names: a browser holding a cached (older) index.*.js
      // keeps loading the chunks it was built with instead of new, incompatible chunks under the
      // same numeric name ("Cannot read properties of undefined (reading 'call')"). Old chunks are not
      // deleted by the build, so they stay available to such browsers until pruned.
      chunkFilename: `[name].[contenthash:8].${mode}.js`,
      publicPath: '/umd/'
    },
    optimization: {
      minimize: (mode === 'prod'),
      minimizer: ['...']
    },
    performance: {
      maxEntrypointSize: maxAssetSize,
      maxAssetSize: maxAssetSize,
      assetFilter: function(assetFilename) {
        // Exclude all sourcemaps
        if (/\.map$/.test(assetFilename)) {
          return false;
        }
        return true;
      },
    },
    plugins: [
      new CopyPlugin({
        patterns: [
          { from: `node_modules/tinode-sdk/umd/tinode.${mode}.js`, to: `tinode.${mode}.js` },
          { from: `node_modules/tinode-sdk/umd/tinode.${mode}.js.map`, to: `tinode.${mode}.js.map` },
        ],
      }),
    ],
    externals: {
      'livekit-client': 'LivekitClient',
      'qrcodejs': 'QRCode',
      'react': 'React',
      'react-dom': 'ReactDOM',
      'react-intl': 'ReactIntl',
      'tinode-sdk': 'tinode',
    },
  };
}
