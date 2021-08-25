#pragma once

#include <ranges>

using namespace std;
using namespace wiECS;
using namespace wiScene;

template<class T>
std::vector<Entity> getEntitiesForParent(Entity parent)
{
	std::vector<Entity> entities;
	for (int i = 0; i < GetScene().hierarchy.GetCount(); i++) {
		auto heirarchyComponent = GetScene().hierarchy[i];
		auto entity = GetScene().hierarchy.GetEntity(i);
		if (heirarchyComponent.parentID == parent) {
			ComponentManager<T>& manager = GetScene().GetManager<T>();
			auto component = manager.GetComponent(entity);
			if (component != nullptr) {
				entities.push_back(entity);
			}
		}
	}
	return entities;
}

template <class T>
const T* componentFromEntity(Entity ent) {
	return GetScene().GetManager<T>().GetComponent(ent);
}

template <class T>
T* mutableComponentFromEntity(Entity ent) {
	auto component = GetScene().GetManager<T>().GetComponent(ent);
	GetScene().WhenMutable(*component);
	return component;
}	

bool isAncestorOfEntity(Entity entity, Entity ancestor) {
	auto heirarchyComponent = GetScene().hierarchy.GetComponent(ancestor);
	if (heirarchyComponent == nullptr) { return false; }
	Entity parent = heirarchyComponent->parentID;
	while (parent != INVALID_ENTITY)
	{
		if (entity == parent) { return true; }
		ancestor = parent;
		auto heirarchyComponent = GetScene().hierarchy.GetComponent(ancestor);
		if (heirarchyComponent == nullptr) { return false; }
		parent = heirarchyComponent->parentID;
	}
	return false;
}

Entity findOffspringWithName(Entity entity, string name) {
	ComponentManager<NameComponent>& manager = GetScene().GetManager<NameComponent>();
	for (int i = 0; i < manager.GetCount(); i++) {
		auto ent = manager.GetEntity(i);
		if (!isAncestorOfEntity(entity, ent)) { continue; }
		auto nameComponent = manager[i];
		if (nameComponent.name.compare(name) == 0) { return ent;  }
	}
	return INVALID_ENTITY;
}

Entity findWithName(string name) {
	ComponentManager<NameComponent>& manager = GetScene().GetManager<NameComponent>();
	for (int i = 0; i < manager.GetCount(); i++) {
		auto nameComponent = manager[i];
		if (nameComponent.name.compare(name) == 0) { return manager.GetEntity(i); }
	}
	return INVALID_ENTITY;
}

auto getAncestryForEntity(Entity child)
{
	vector<Entity> ancestry{};
	Entity next = child;
	while (next != INVALID_ENTITY) {
		ancestry.push_back(next);
		auto component = componentFromEntity<HierarchyComponent>(next);
		if (component == nullptr) { break; }
		next = component->parentID;
	}
	return vector<Entity>(ancestry.rbegin(), ancestry.rend());
}

class MatrixAggregator {
	XMMATRIX aggregateMatrix = XMMatrixIdentity();
public:
	const function<XMMATRIX(Entity)> Transform = [&](Entity entity) {
		auto trans = componentFromEntity<TransformComponent>(entity);
		XMMATRIX localMatrix = trans->GetLocalMatrix();
		aggregateMatrix = XMMatrixMultiply(aggregateMatrix, localMatrix);
		return aggregateMatrix;
	};
};
