#!/usr/bin/env node
/**
 * 战棋 · 反向隧道中继（relay）—— 让「房主在 NAT 后」也能被公网连到
 * ============================================================
 * 解决的场景：房主在自己家/宿舍的路由器后面，公网连不进来。
 * 房主**主动连出**到本服务，本服务再把它"挂"到一个公网端口上，
 * 外部玩家连那个端口即等于连到房主。
 *
 * 拓扑：
 *
 *   房主 Godot ──桥接器──> 本服务 :19001（房主入口，房主主动连出，与 NAT 无关）
 *                              │ 分配一个公网端口 P，并把 P 上的连接与房主配对
 *   玩家 Godot ──────ws─────> 本服务 :P（公网入口，P ∈ 20000..20099）
 *
 * 本服务**只做字节转发**，不碰游戏逻辑、不参与同步、不做裁决
 * （与房间号服务同一条原则：服务器只做信令/中继）。
 *
 * 协议（房主入口，全是换行分隔的文本控制行）：
 *   服务 → 房主： "PORT <p>\n"      分配给你的公网端口
 *   服务 → 房主： "HOST <ip>\n"     对外报告用的公网地址
 *   服务 → 房主： "GO\n"            有玩家进来了，去连你自己的本地端口开始桥接
 *   服务 → 房主： "BUSY\n"          端口池满了
 *   GO 之后这条连接上**不再有控制行**，全是原始字节（对局数据）。
 *
 * 环境变量：
 *   CONTROL_PORT  房主入口端口，默认 19001
 *   POOL_START    公网端口池起始，默认 20000
 *   POOL_END      公网端口池结束，默认 20099
 *   PUBLIC_HOST   写进地址里的公网 IP/域名，默认 127.0.0.1（本机自测用）
 */

const net = require("node:net");

const CONTROL_PORT = Number(process.env.CONTROL_PORT || 19001);
const POOL_START = Number(process.env.POOL_START || 20000);
const POOL_END = Number(process.env.POOL_END || 20099);
const PUBLIC_HOST = process.env.PUBLIC_HOST || "127.0.0.1";

/** port -> { port, hostConn, pubSrv, paired } */
const slots = new Map();

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function allocPort() {
  for (let p = POOL_START; p <= POOL_END; p++) {
    if (!slots.has(p)) return p;
  }
  return 0;
}

const controlSrv = net.createServer((hostConn) => {
  const port = allocPort();
  if (!port) {
    log("端口池已满，拒绝一个房主");
    hostConn.write("BUSY\n");
    hostConn.end();
    return;
  }

  const slot = { port: port, hostConn: hostConn, pubSrv: null, paired: false };
  slots.set(port, slot);

  // 该房间专属的公网入口
  const pubSrv = net.createServer((playerConn) => {
    if (slot.paired) {
      log(`端口 ${port} 已经有玩家了，拒绝多余的连接（本作是 1V1）`);
      playerConn.destroy();
      return;
    }
    slot.paired = true;
    log(`端口 ${port} 配对成功 → 通知房主开桥并开始转发`);
    hostConn.write("GO\n");
    playerConn.pipe(hostConn);
    hostConn.pipe(playerConn);
    playerConn.on("error", () => {});
    hostConn.on("error", () => {});
    playerConn.on("close", () => hostConn.destroy());
    hostConn.on("close", () => playerConn.destroy());
  });
  slot.pubSrv = pubSrv;

  pubSrv.listen(port, () => {
    log(`房主接入，分配公网端口 ${port}（当前占用 ${slots.size} 个）`);
    hostConn.write("PORT " + port + "\n");
    hostConn.write("HOST " + PUBLIC_HOST + "\n");
  });

  pubSrv.on("error", (e) => {
    log(`端口 ${port} 监听失败：${e.message}`);
    hostConn.write("BUSY\n");
    hostConn.end();
    release();
  });

  function release() {
    if (!slots.has(port)) return;
    slots.delete(port);
    try { pubSrv.close(); } catch (e) { /* already closed */ }
    log(`端口 ${port} 已释放（剩余占用 ${slots.size} 个）`);
  }

  hostConn.on("close", release);
  hostConn.on("error", release);
});

controlSrv.listen(CONTROL_PORT, () => {
  log(`房主入口 ${CONTROL_PORT} 就绪；公网端口池 ${POOL_START}-${POOL_END}；对外地址 ${PUBLIC_HOST}`);
  log(`自检：房主连 ${CONTROL_PORT} 后应收到 "PORT <端口>" 与 "HOST <地址>"`);
});
