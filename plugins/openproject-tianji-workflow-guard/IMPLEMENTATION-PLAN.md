# OpenProject 17.9.2 合同门禁实施边界

状态：**未批准研究候选，禁止部署或加载。** 根代理最初允许本地研究代码，随后复核原 PRD UPG-01/UPG-02/D.3，指出内部合同 callback 和尤其 prepend `validate` 包装并非已有官方稳定 SPI 证据；现已暂停全部远程运行验证。没有获批 PRD 例外，也没有批准生产部署、生产脚本注入、密钥签发、账号或 executor 成员授权。入口/Engine 无条件拒绝加载。FR-01/FR-12/UPG 尚未通过。下文描述研究候选，不是已批准接口。

## 插入点

使用独立 GPL-3.0 Rails Engine gem，经官方 `OpenProject::Plugins::ActsAsOpEngine` 的 `patch_with_namespace` 注册。正常 Create/Update/Copy/Form 合同继承 `WorkPackages::BaseContract`，追加一个独立验证回调，保留上游所有检查。`CreateService` 在合同成功后以 `validate: false` 保存，不能只增加模型 validator。

新增实际源码发现：`WorkPackages::UpdateDependentContract#validate` 直接返回 true，继承回调不会执行。因此还要通过同一官方插件注册机制，为这个具体类 prepend 一层 `validate` 包装：先保留原返回值，再执行同一 guard；不重新启用原本故意跳过的全部模型/业务校验。隔离测试必须证明这个真实 override 路径也被门禁覆盖。`valid?` 回调和 `validate` 包装都不能接受由请求决定的 skip 标记。

不修改 vendor、上游核心源文件、Enterprise 功能开关或业务表结构；没有业务表直写或独立保存入口。插件仅读取当前身份、成员、角色、工作流、项目类型和状态，由原生服务决定最终持久化。

## 最小接口

`Guard.validate(model:, user:)` 只由受审查的合同 hook 调用，负责把有界错误代码加到原合同 errors。`RailsAuthority.capture` 从真实模型及数据库重新构造原记录、当前用户、真实角色和工作流；`Policy.evaluate` 只处理不可变内部快照并返回固定拒绝代码。没有 HTTP 接口接受任意快照、actor_id、allowed 布尔或角色清单。

配置必须绑定固定项目 IDs、types 8–13、状态完整分类、真实项目角色 IDs/权限及各 type 默认/作者/受理人矩阵。空项目、空角色、未知字段、源文件 SHA/版本变化、矩阵漂移不能启动或允许受管写入。样例占位配置不可以直接部署。

范围取原记录与目标记录的并集；从受管项目或 type 改出，仍经过门禁。初版拒绝跨项目/受管类型目录迁出入；同一项目内六类型正常互换保留，里程碑日期等原生约束继续生效。

创建只能使用当前批准的默认开放状态 1，不能初始进入观察中、任意 closed 或其他非默认状态。复制新记录同样适用。

更新使用真实持久原 project/type/status/author/assignee 和当前身份重新获取的角色。状态变化时，原 type 的原状态到目标状态的真实角色边，以及目标 type 的对应边，都必须存在且属于批准矩阵；不因请求同时含 type 而省略检查。状态不变的合法普通 type 变更仍可进行，但目标 type 必须真正启用且含该开放状态。作者/受理人资格取原值，不能靠同一请求重新分配获取附加边。额外遗留/全局/未知角色不自动扩大允许范围。

完整状态目录采用真实 `is_closed?`/`is_default?` 分类，不能只保护 ID 12。所有 closed 和受控观察状态 17 的进入始终需要独立授权后端；executor 角色或 actor ID 本身不构成授权。当前后端不存在，默认固定拒绝，不提供 dummy allow、模拟签名或开发模式旁路。

已经在 17/closed 的事实、类型、版本、证据和其他会改变工作项修订的变更，需先获得权威作废与回退授权。当前只提供默认拒绝边界，不宣称新部署自动回退已交付。普通开放阶段的 subject/description 编辑、同项目合法 type 编辑及原生 status-only 权限保留；审批/只读用户不能因 guard 获得新的原生权限。

## FR-12 后续独立授权后端

完整 Bridge 仍须在工作项串行锁下，重新读取真实 deployment_id、生产站点/环境/Digest、验证及证据摘要、观察时长、多方确认、当前 ACL、告警和策略修订，记录持久意图、真实 lockVersion，并在未知写入结果后对账。新部署在 16 保持 16，在 17/closed 回到 16 并使旧验证失效；不能伪造“验证失败”。关闭版本的原生禁止重开约束需通过批准的原生版本操作顺序解决，不能关闭原生验证。

未来许可证式授权必须经受控服务的密码学校验，绑定 audience、工作项/项目/type、原状态、目标状态、原 lockVersion、精确变更摘要、部署/验证/策略/ACL修订、短期时限和单次 nonce；完成权威复核、重放防护及事务边界前，不实现允许分支。actor 固定 ID 只是身份边界。插件本身不能把异步跨平台事实变成原子事务，关闭后仍须监测、撤销与异常队列。

## 测试层级与执行限制

1. 纯 Ruby 决策测试：合成内部快照，覆盖默认创建、所有 closed、新未知状态、30 个有序类型对、原/目标双矩阵、原作者/受理人、多角色、额外角色、普通编辑、status-only、同项目范围、17/closed 修改和无授权后端拒绝。它们只能证明决策代码。
2. 相同运行镜像中加载真实 Engine/合同：验证官方补丁注册、真实继承链与回调、`UpdateDependentContract#validate` 的 override，以及 `validate:false` 前原生服务失败传播。仅使用隔离容器和合成对象，不能冒充真实数据库/API验收。
3. 相同镜像、独立空 PG、隔离 Rails 应用：从官方服务/正式 API 创建自有 fixtures，实际非管理员执行 Create/Update/Form/Copy/Bulk/Dependent/lockVersion，逐次读取真实记录与 journal；拒绝须来自本 guard，不能用无效日期、旧锁或未授权原生接口替代。分别覆盖 Web 和 worker，未知版本/缺 hook/错误配置启动失败。需要审查后再启动环境。

候选宿主是 10.106.1.185；目前仅允许只读检查运行时/缓存镜像/磁盘资源。候选 OpenProject imageID 为生产容器实际 `sha256:b1cf0fe04686a7effcab3ad793cde5ab61c5d654dd153c87463fc43b98ca0a86`，还必须取得可拉取的 manifest digest，不能把 image config ID 当 manifest。Root 审查具体宿主、两个镜像 digest、独立网络 namespace、默认拒绝外联、无 hostNetwork/hostPID/hostIPC、无生产 env/Secret/PVC/目录挂载、唯一前缀、自有临时目录和资源上限后才允许运行。

同版本测试不是在生产 Pod 内启动 Rails，也不复制生产数据库；临时 PG 仅含自己新建的测试数据。清理只针对已核对唯一前缀及自有对象，不影响 Runner 的 paused、config、网络、现有容器或工作目录。

## 来源

实际运行 Pod UID `19f9a4da-1ee0-4a40-bc4b-beb53db115d0` 公开源码的只读回执保存在外层 `openproject-guard-source-20261017/receipt.json` 和 `openproject-guard-additional-source-20261017/receipt.json`；没有生产 Rails boot、业务数据库访问或写入。安装源 SHA 是本次兼容边界，不能假定公共 tag 字节相同。

- [官方插件开发](https://www.openproject.org/docs/development/create-openproject-plugin/)
- [官方插件配置](https://www.openproject.org/docs/installation-and-operations/configuration/plugins/)
- [17.9.2 Engine 注册机制](https://raw.githubusercontent.com/opf/openproject/v17.9.2/lib/open_project/plugins/acts_as_op_engine.rb)
- [17.9.2 CreateService](https://raw.githubusercontent.com/opf/openproject/v17.9.2/app/services/work_packages/create_service.rb)
