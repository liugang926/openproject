# 未批准研究候选：OpenProject 合同门禁

**禁止部署、加载或据此修改生产权限。** 本目录是对 17.9.2 内部合同保存路径的研究候选，没有获批 PRD 例外。入口和 Engine 文件均无条件拒绝加载。

原 PRD 的 UPG-01 禁止未经事前审批的 Monkey Patch/核心方法替换，UPG-02 不把内部 public 类视作稳定接口，D.3 还明确禁止覆盖 OpenProject 核心状态机。官方支持 Gem/Rails Engine 包装不等于承诺 `WorkPackages::BaseContract` 或 `UpdateDependentContract#validate` 是稳定验证 SPI。当前候选的内部 callback 依赖和 prepend 包装存在该冲突，尚未证明合规。

`lib/.../config.rb`、`policy.rb` 与 `test/policy_test.rb` 可独立审查纯 Ruby 决策行为；合成测试不能证明真实服务/API、防绕过、FR-12 或 UPG 通过。没有独立密码学授权后端，任何 executor 身份也不能放行进入观察或 closed。

保留文件用于具体例外评审和寻求官方替代接口，不应加入生产镜像、Gemfile 或部署清单。生产关闭边保持未启用。测试环境也须经 Root 审查，不能通过隔离运行把未经批准的候选变成允许投产的方案。

当前无生产写入、无生产 Rails boot、无新增生产账号/Token/签名 Key、无容器启动。详细范围见 [实施研究计划](IMPLEMENTATION-PLAN.md)。
