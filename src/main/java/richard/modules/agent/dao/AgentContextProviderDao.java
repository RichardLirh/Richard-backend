package richard.modules.agent.dao;

import org.apache.ibatis.annotations.Mapper;
import richard.common.dao.BaseDao;
import richard.modules.agent.entity.AgentContextProviderEntity;

@Mapper
public interface AgentContextProviderDao extends BaseDao<AgentContextProviderEntity> {
}
