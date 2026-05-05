module.exports = {
  apps: [
    {
      name: "stargate-control-server",
      script: "server.js",
      cwd: __dirname,
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "200M",
      env: {
        NODE_ENV: "production",
        HOST: "0.0.0.0",
        PORT: "2088",
        AUTO_UPDATE_ENABLED: "false",
        AUTO_UPDATE_MANIFEST_URL: "",
        AUTO_UPDATE_INTERVAL_MS: "300000"
      }
    }
  ]
};
