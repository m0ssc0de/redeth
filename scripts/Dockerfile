FROM yesq/ethereumetl:2.1.1

RUN apk add curl bash redis
RUN curl https://sdk.cloud.google.com > install.sh && bash install.sh --disable-prompts
ENV PATH="/root/google-cloud-sdk/bin/:${PATH}"
COPY worker.sh sorter.sh /