package richard.modules.agent.service.impl;

import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;

import richard.common.service.impl.BaseServiceImpl;
import richard.modules.agent.dao.AgentContextProviderDao;
import richard.modules.agent.entity.AgentContextProviderEntity;
import richard.modules.agent.service.AgentContextProviderService;

@Service
public class AgentContextProviderServiceImpl extends BaseServiceImpl<AgentContextProviderDao, AgentContextProviderEntity> implements AgentContextProviderService {

    @Override
    public AgentContextProviderEntity getByAgentId(String agentId) {
        return baseDao.selectOne(new QueryWrapper<AgentContextProviderEntity>().eq("agent_id", agentId));
    }

    @Override
    public void saveOrUpdateByAgentId(AgentContextProviderEntity entity) {
        AgentContextProviderEntity exist = getByAgentId(entity.getAgentId());
        if (exist != null) {
            entity.setId(exist.getId());
            updateById(entity);
        } else {
            insert(entity);
        }
    }

    @Override
    public void deleteByAgentId(String agentId) {
        baseDao.delete(new QueryWrapper<AgentContextProviderEntity>().eq("agent_id", agentId));
    }
}
