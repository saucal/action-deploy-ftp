

(async function() {

	const core = require('@actions/core');
	const path = require('path');
	const fs = require('fs');
	const ftpClient = require('ftp-deployment/client');

	class cliFTPClient extends ftpClient {
		constructor() {
			super( {
				type: core.getInput('env-type', { required: false }),
				host: core.getInput('env-host', { required: true }),
				port: core.getInput('env-port', { required: true }),
				username: core.getInput('env-user', { required: true }),
				password: core.getInput('env-pass', { required: true }),
				remoteRoot: core.getInput('env-remote-root', { required: true }),
				localRoot: core.getInput('env-local-root', { required: true }),
				debug: core.isDebug() ? (msg) => {
					if (msg.startsWith('CLIENT')) {
						console.error(msg);
					}
				} : undefined,
			} );
		}
	}


	function readData() {
		let input = core.getInput('manifest', { required: true });
		if ( input.startsWith( "+" ) || input.startsWith( "-" ) ) {
			return require('stream').Readable.from( [ input ] );
		} else {
			return fs.createReadStream( path.resolve( input ) )
		}
	}

	const client = new cliFTPClient();

	client
		.maybeConnect()
		.then( function() {
			return client.process( readData(), {
				ignore: core.getInput('force-ignore', { required: false })
			} );
		} )
		.then( function() {
			return client.end()
		} )

})()
