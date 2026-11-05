# Kernel configuration

The project configuration is derived deterministically from the pinned
Raspberry Pi `bcm2711_defconfig`.

Authoritative project delta:

`uconsole-cm4.config`

The build procedure is:

1. prepare the exact pinned Raspberry Pi Linux source;
2. install the project drivers/overlay and apply patches `0001` through `0005`;
3. run `make bcm2711_defconfig`;
4. merge `uconsole-cm4.config`;
5. run `make olddefconfig`;
6. verify every required uConsole symbol resolved to the intended value.

Do not replace this with a copied full `.config`. The small fragment keeps the
project delta auditable and lets the Raspberry Pi baseline evolve explicitly
when the pinned source is updated.
