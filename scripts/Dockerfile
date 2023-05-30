FROM yesq/scripts:base
COPY default.nix worker.sh sorter.sh /
# COPY worker.sh /worker.sh
# RUN nix-shell /default.nix
CMD ["/worker.sh"]
