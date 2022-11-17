npm i -g saucal/ftp-deployment
ftp-deployment-cli --type="${{ inputs.env-type }}" --host="${{ inputs.env-host }}" --port="${{ inputs.env-port }}" --user="${{ inputs.env-user }}" --pass="${{ inputs.env-pass }}" --remote-root="${{ inputs.env-remote-root }}" --local-root="${{ inputs.target }}" "deploy.manifest"
