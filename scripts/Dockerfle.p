FROM yesq/ethereumetl:2.1.1

RUN apk add curl bash redis
RUN curl https://sdk.cloud.google.com > install.sh && bash install.sh --disable-prompts
COPY worker.sh sorter.sh /