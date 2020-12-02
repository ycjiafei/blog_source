FROM node:latest
RUN npm install -g cnpm --registry=https://registry.npm.taobao.org
RUN cnpm install hexo-cli -g
