

(async function() {

	const exec = require('@actions/exec');
	const core = require('@actions/core');
	const path = require('path');
	core.addPath( path.resolve( __dirname ) );

	await exec.exec('main.sh', [ core.getInput('token', { required: true }) ]);

})()
