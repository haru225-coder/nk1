# 船体改装系统 - 实施追踪

## 步骤
- [x] 探索完成（Fleet/Main/Voyage/SeaChart/Ship/校验全部读完）
- [x] 计划批准
- [ ] 1. Fleet.gd：常量 + 只读 API + upgrade_* + 成本 + armor 辅助
- [ ] 2. Voyage.gd + SeaChart.gd：armor 消费点
- [ ] 3. Main.gd：船屋 UI + _on_upgrade + 状态面板
- [ ] 4. simulate_run.py：speed 加成 + 独立升级模拟段
- [ ] 5. verify_economy.py：六之四
- [ ] 6. check_symbols.py：五之三
- [ ] 7. 三套校验收口

## 验证方式
cd ~/nk-1 && python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py
