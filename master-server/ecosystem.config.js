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
        PROGRAM_UPDATE_SOURCE_URL: "https://raw.githubusercontent.com/Minecrafter8001/dialing-computer-new-the-third-one/refs/heads/main/program/"
      }
    }
  ]
};
