FROM node:latest
RUN npm install -g cnpm --registry=https://registry.npm.taobao.org \
&& cnpm install hexo-cli -g \
&& cnpm install hexo-deployer-git --save \
&& git config --global user.email "jiafei@docker.com" \
&& git config --global user.name "jiafeiDocker"
